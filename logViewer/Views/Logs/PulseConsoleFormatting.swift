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
    @State private var query = PulseNetworkConsoleQuery()
    @State private var expandedSections: Set<String> = []
    @Binding var selection: PulseConsoleSelection?

    init(context: NSManagedObjectContext, selection: Binding<PulseConsoleSelection?>) {
        _controller = StateObject(wrappedValue: PulseNetworkQueryController(context: context))
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
            } else if query.grouping == .none {
                Table(controller.tasks, selection: networkSelection) {
                    TableColumn("Method") { task in
                        Text(task.methodDisplayText)
                            .font(.caption.weight(.semibold))
                    }
                    .width(min: 72, ideal: 84)

                    TableColumn("Host") { task in
                        Text(task.hostDisplayText)
                            .lineLimit(1)
                    }
                    .width(min: 140, ideal: 180)

                    TableColumn("Request") { task in
                        Text(task.primaryURLText)
                            .lineLimit(1)
                    }
                    .width(min: 220, ideal: 320)

                    TableColumn("Status") { task in
                        Text(task.statusDisplayText)
                            .foregroundStyle(task.statusAccentColor)
                    }
                    .width(min: 72, ideal: 84)

                    TableColumn("Duration") { task in
                        Text(task.durationText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Size") { task in
                        Text(task.sizeDisplayText)
                            .font(.caption.monospacedDigit())
                    }
                    .width(min: 90, ideal: 110)

                    TableColumn("Date") { task in
                        Text(task.formattedTimestamp)
                            .font(.caption.monospacedDigit())
                    }
                    .width(min: 140, ideal: 160)

                    TableColumn("Error") { task in
                        Text(task.errorDisplayText)
                            .lineLimit(1)
                            .foregroundStyle(task.state == .failure ? .red : .secondary)
                    }
                    .width(min: 180, ideal: 220)
                }
            } else {
                List(selection: $selection) {
                    ForEach(groupedSections) { section in
                        Section {
                            if expandedSections.contains(section.id) {
                                ForEach(section.tasks) { task in
                                    PulseNetworkRowView(task: task)
                                        .tag(PulseConsoleSelection.network(task.objectID))
                                }
                            }
                        } header: {
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
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
            }
        }
        .onChange(of: query) { controller.apply(query: $0) }
        .onChange(of: query.grouping) { _ in
            expandedSections = Set(groupedSections.map(\.id))
        }
        .onChange(of: groupedSections.map(\.id)) { ids in
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

    private var networkSelection: Binding<NSManagedObjectID?> {
        Binding(
            get: {
                guard case let .network(objectID) = selection else {
                    return nil
                }
                return objectID
            },
            set: { objectID in
                selection = objectID.map(PulseConsoleSelection.network)
            }
        )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.methodDisplayText)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(task.primaryURLText)
                        .font(.headline)
                        .lineLimit(1)

                    Text(task.secondaryNetworkSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(task.formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    Text(task.statusDisplayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(task.statusAccentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(task.statusAccentColor.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 12) {
                Label(task.sizeDisplayText, systemImage: "arrow.down.circle")
                Label(task.responseHeaderSummary, systemImage: "rectangle.compress.vertical")
                Label(task.durationText, systemImage: "timer")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
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
