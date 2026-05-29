import SwiftUI

#if os(macOS) && canImport(Pulse)
import CoreData
import Pulse

struct PulseConsoleHostView: View {
    let injector: PulseStoreInjector
    let category: LogCategory
    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        Group {
            switch category {
            case .messages:
                PulseMessagesConsoleView(selection: $selection)
            case .network:
                PulseNetworkConsoleView(
                    context: injector.store.viewContext,
                    blocklist: injector.blocklist,
                    selection: $selection
                )
            }
        }
        .environment(\.managedObjectContext, injector.store.viewContext)
        .id(category)
    }
}

private struct PulseMessagesConsoleView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\LoggerMessageEntity.createdAt, order: .reverse)],
        predicate: NSPredicate(format: "task == NULL"),
        animation: .default
    )
    private var messages: FetchedResults<LoggerMessageEntity>

    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        if messages.isEmpty {
            PulseEmptyStateView(
                title: "No Messages Yet",
                subtitle: "收到来自 iPhone 的普通日志后，这里会按 Pulse 风格实时追加。"
            )
        } else {
            List(messages, selection: $selection) { message in
                PulseMessageRowView(message: message)
                    .tag(PulseConsoleSelection.message(message.objectID))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

private struct PulseNetworkConsoleView: View {
    @StateObject private var controller: PulseNetworkQueryController
    @ObservedObject private var blocklist: NetworkRequestBlocklist
    @State private var query = PulseNetworkConsoleQuery()
    @State private var expandedSections: Set<String> = []
    @Binding var selection: PulseConsoleSelection?

    init(
        context: NSManagedObjectContext,
        blocklist: NetworkRequestBlocklist,
        selection: Binding<PulseConsoleSelection?>
    ) {
        _controller = StateObject(
            wrappedValue: PulseNetworkQueryController(context: context, blocklist: blocklist.snapshot)
        )
        _blocklist = ObservedObject(wrappedValue: blocklist)
        _selection = selection
    }

    var body: some View {
        VStack(spacing: 0) {
            networkToolbar
                .padding(12)

            Divider()

            if controller.tasks.isEmpty {
                PulseEmptyStateView(
                    title: "No Network Traffic Yet",
                    subtitle: "收到远端网络摘要后，这里会显示请求、状态码、头信息与响应体预览。"
                )
            } else {
                List {
                    if query.grouping == .none {
                        ForEach(controller.tasks) { task in
                            networkRow(task)
                        }
                    } else {
                        ForEach(groupedSections) { section in
                            Section {
                                if expandedSections.contains(section.id) {
                                    ForEach(section.tasks) { task in
                                        networkRow(task)
                                    }
                                }
                            } header: {
                                groupHeader(for: section)
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .onChange(of: query) { _, newQuery in
            controller.apply(query: newQuery, blocklist: blocklist.snapshot)
        }
        .onChange(of: blocklist.snapshot) { _, snapshot in
            controller.apply(query: query, blocklist: snapshot)
        }
        .onChange(of: query.grouping) { _, _ in
            expandedSections = Set(groupedSections.map(\.id))
        }
        .onChange(of: controller.tasks.map(\.objectID)) { _, visibleTaskIDs in
            guard case let .network(objectID) = selection else {
                return
            }

            if !visibleTaskIDs.contains(objectID) {
                selection = nil
            }
        }
        .onChange(of: groupedSections.map(\.id)) { _, ids in
            let next = Set(ids)
            if expandedSections.isEmpty {
                expandedSections = next
            } else {
                expandedSections.formIntersection(next)
            }
        }
    }

    private var groupedSections: [PulseNetworkGroupSection] {
        controller.makeSections(grouping: query.grouping)
    }

    private var networkToolbar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                TextField("Search URL, host, method, error…", text: $query.searchText)
                    .textFieldStyle(.roundedBorder)
                    .frame(minWidth: 220, idealWidth: 280)

                Menu {
                    Button("Any Status") {
                        query.statusFilters.removeAll()
                    }
                    Divider()
                    ForEach(PulseNetworkStatusFilter.allCases) { filter in
                        Toggle(filter.title, isOn: statusBinding(for: filter))
                    }
                } label: {
                    filterPill(title: "Status", value: statusFilterTitle)
                }

                Menu {
                    Button("Any Method") {
                        query.methodFilters.removeAll()
                    }
                    Divider()
                    ForEach(controller.availableMethods, id: \.self) { method in
                        Toggle(method, isOn: methodBinding(for: method))
                    }
                } label: {
                    filterPill(title: "Method", value: methodFilterTitle)
                }

                Menu {
                    Button("Any Host") {
                        query.hostFilters.removeAll()
                    }
                    Divider()
                    ForEach(controller.availableHosts, id: \.self) { host in
                        Toggle(host, isOn: hostBinding(for: host))
                    }
                } label: {
                    filterPill(title: "Host", value: hostFilterTitle)
                }

                Spacer(minLength: 12)

                Text("\(controller.tasks.count) items")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Picker("Duration", selection: $query.durationFilter) {
                    ForEach(PulseNetworkDurationFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 130)

                Picker("Size", selection: $query.sizeFilter) {
                    ForEach(PulseNetworkSizeFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 140)

                Picker("Error", selection: $query.errorFilter) {
                    ForEach(PulseNetworkErrorFilter.allCases) { filter in
                        Text(filter.title).tag(filter)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Picker("Group", selection: $query.grouping) {
                    ForEach(PulseNetworkGrouping.allCases) { group in
                        Text(group.title).tag(group)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Picker("Sort", selection: $query.sortField) {
                    ForEach(PulseNetworkSortField.allCases) { field in
                        Text(field.title).tag(field)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 110)

                Picker("Direction", selection: $query.sortDirection) {
                    ForEach(PulseNetworkSortDirection.allCases) { direction in
                        Text(direction.title).tag(direction)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer(minLength: 12)

                Button("Reset Filters") {
                    query = PulseNetworkConsoleQuery()
                }
            }
        }
    }

    private var statusFilterTitle: String {
        query.statusFilters.isEmpty ? "Any" : query.statusFilters.map(\.title).sorted().joined(separator: ", ")
    }

    private var methodFilterTitle: String {
        query.methodFilters.isEmpty ? "Any" : query.methodFilters.sorted().joined(separator: ", ")
    }

    private var hostFilterTitle: String {
        guard !query.hostFilters.isEmpty else {
            return "Any"
        }
        if query.hostFilters.count == 1, let host = query.hostFilters.first {
            return host
        }
        return "\(query.hostFilters.count) selected"
    }

    private func filterPill(title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .lineLimit(1)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }

    private func toggleSection(_ id: String) {
        if expandedSections.contains(id) {
            expandedSections.remove(id)
        } else {
            expandedSections.insert(id)
        }
    }

    private func groupHeader(for section: PulseNetworkGroupSection) -> some View {
        Button {
            toggleSection(section.id)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: expandedSections.contains(section.id) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text(section.title)
                    .font(.subheadline.weight(.semibold))

                Spacer()

                Text("\(section.tasks.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .textCase(nil)
    }

    private func networkRow(_ task: NetworkTaskEntity) -> some View {
        PulseNetworkRowView(
            task: task,
            isSelected: selection == .network(task.objectID),
            blocklist: blocklist,
            deleteAction: {
                controller.delete(taskWithID: task.objectID)
            }
        )
        .onTapGesture {
            selection = .network(task.objectID)
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10))
        .listRowBackground(Color.clear)
    }

    private func statusBinding(for filter: PulseNetworkStatusFilter) -> Binding<Bool> {
        Binding(
            get: { query.statusFilters.contains(filter) },
            set: { isEnabled in
                if isEnabled {
                    query.statusFilters.insert(filter)
                } else {
                    query.statusFilters.remove(filter)
                }
            }
        )
    }

    private func methodBinding(for method: String) -> Binding<Bool> {
        Binding(
            get: { query.methodFilters.contains(method) },
            set: { isEnabled in
                if isEnabled {
                    query.methodFilters.insert(method)
                } else {
                    query.methodFilters.remove(method)
                }
            }
        )
    }

    private func hostBinding(for host: String) -> Binding<Bool> {
        Binding(
            get: { query.hostFilters.contains(host) },
            set: { isEnabled in
                if isEnabled {
                    query.hostFilters.insert(host)
                } else {
                    query.hostFilters.remove(host)
                }
            }
        )
    }
}

private struct PulseMessageRowView: View {
    let message: LoggerMessageEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.label.isEmpty ? "Remote Log" : message.label)
                        .font(.headline)
                        .lineLimit(1)

                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    Text(message.logLevelTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(message.logLevelColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(message.logLevelColor.opacity(0.12), in: Capsule())
                }
            }

            if !message.metadata.isEmpty {
                Text(message.metadataText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PulseNetworkRowView: View {
    let task: NetworkTaskEntity
    let isSelected: Bool
    @ObservedObject var blocklist: NetworkRequestBlocklist
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                HStack(spacing: 8) {
                    capsule(title: task.methodDisplayText, tint: .secondary)
                    capsule(title: task.statusDisplayText, tint: task.statusAccentColor)
                }

                Text(task.hostDisplayText)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(task.formattedTimestamp)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }

            Text(task.primaryURLText)
                .font(.headline)
                .lineLimit(4)
                .fixedSize(horizontal: false, vertical: true)

            Text(task.secondaryNetworkSummary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            HStack(spacing: 14) {
                metricLabel(task.sizeDisplayText, systemImage: "arrow.down.circle")
                metricLabel(task.responseHeaderSummary, systemImage: "rectangle.compress.vertical")
                metricLabel(task.durationText, systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(cardStrokeColor, lineWidth: 1)
        }
        .shadow(color: cardShadowColor, radius: isSelected ? 14 : 6, y: isSelected ? 4 : 2)
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .animation(.easeInOut(duration: 0.16), value: isSelected)
        .contextMenu {
            Menu("Add to Blacklist") {
                if let normalizedHost = task.normalizedHostValue {
                    Button("Add Host: \(normalizedHost)") {
                        _ = blocklist.addHost(normalizedHost)
                    }
                }

                if let normalizedURL = task.normalizedURLValue {
                    Button("Add URL") {
                        _ = blocklist.addURL(normalizedURL)
                    }
                }

                if task.normalizedHostValue == nil, task.normalizedURLValue == nil {
                    Button("No blacklist target available") {}
                        .disabled(true)
                }
            }

            Divider()

            Button("Delete Request", role: .destructive, action: deleteAction)
        }
    }

    private var cardBackground: Color {
        isSelected ? Color.accentColor.opacity(0.10) : Color(nsColor: .controlBackgroundColor)
    }

    private var cardStrokeColor: Color {
        isSelected ? Color.accentColor.opacity(0.65) : Color.black.opacity(0.06)
    }

    private var cardShadowColor: Color {
        isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.05)
    }

    private func capsule(title: String, tint: Color) -> some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12), in: Capsule())
    }

    private func metricLabel(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
    }
}

private struct PulseEmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#else
struct PulseConsoleHostView: View {
    let injector: PulseStoreInjector
    let category: LogCategory
    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Pulse Not Linked")
                .font(.headline)

            Text("当前 target 未链接 Pulse，无法构建自定义 Console。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Store: \(injector.storeDescription)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
#endif
