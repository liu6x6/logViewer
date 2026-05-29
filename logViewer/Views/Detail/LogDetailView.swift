import SwiftUI
#if os(macOS) && canImport(Pulse)
import AppKit
import Pulse
#endif

private enum DetailTab: String, CaseIterable, Hashable {
    case request = "Request"
    case response = "Response"
    case metrics = "Metrics"
}

struct LogDetailView: View {
    let device: DeviceModel?
    let latestPayloadPreview: String?
    let selectedConsoleSelection: PulseConsoleSelection?
    let injector: PulseStoreInjector

    @State private var selectedTab: DetailTab = .request
    @State private var saveErrorMessage: String?

    var body: some View {
        content
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .alert(
            "Failed to Save Response",
            isPresented: Binding(
                get: { saveErrorMessage != nil },
                set: { isPresented in
                    if !isPresented {
                        saveErrorMessage = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(saveErrorMessage ?? "Unknown error")
        }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(device?.name ?? "Inspector")
                    .font(.title3.weight(.semibold))

                Text(inspectorSummaryText)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    DetailChip(title: "Device", value: device?.name ?? "Unknown")
                    DetailChip(title: "Status", value: device?.status.title ?? "Unknown")
                    DetailChip(title: "Rate", value: device?.transferRateText ?? "0 KB/s")
                }
            }

            TabView(selection: $selectedTab) {
                requestDetailPane
                    .tabItem { Text(DetailTab.request.rawValue) }
                    .tag(DetailTab.request)

                responseDetailPane
                    .tabItem { Text(DetailTab.response.rawValue) }
                    .tag(DetailTab.response)

                detailPane(text: metricsTabText)
                    .tabItem { Text(DetailTab.metrics.rawValue) }
                    .tag(DetailTab.metrics)
            }
        }
        .onChange(of: selectedConsoleSelection) { _, _ in
            selectedTab = .request
        }
    }

    @ViewBuilder
    private func detailPane<Actions: View>(text: String, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            actions()

            ScrollView {
                Text(text)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(.thinMaterial)
                    )
            }
        }
    }

    private func detailPane(text: String) -> some View {
        detailPane(text: text) {
            EmptyView()
        }
    }

    @ViewBuilder
    private var requestDetailPane: some View {
        #if os(macOS) && canImport(Pulse)
        switch selectedPayload {
        case .network(let task):
            VStack(alignment: .leading, spacing: 12) {
                requestActions(for: task)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        requestOverviewCard(for: task)

                        DetailSectionCard(
                            title: "Request Headers",
                            subtitle: "\(task.requestHeaderCount) headers"
                        ) {
                            MonospacedDetailText(text: task.requestHeadersText)
                        }

                        DetailSectionCard(
                            title: "Request Body",
                            subtitle: task.requestBodySize.byteCountString
                        ) {
                            MonospacedDetailText(text: task.requestBodyPreviewText)
                        }

                        DetailSectionCard(
                            title: "cURL",
                            subtitle: "Chrome-style request command"
                        ) {
                            MonospacedDetailText(text: task.curlCommandText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
        default:
            detailPane(text: requestTabText)
        }
        #else
        detailPane(text: requestTabText)
        #endif
    }

    @ViewBuilder
    private var responseDetailPane: some View {
        #if os(macOS) && canImport(Pulse)
        switch selectedPayload {
        case .network(let task):
            VStack(alignment: .leading, spacing: 12) {
                responseActions(for: task)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        responseOverviewCard(for: task)

                        DetailSectionCard(
                            title: "Response Headers",
                            subtitle: "\(task.response?.headers.count ?? 0) headers"
                        ) {
                            MonospacedDetailText(text: task.responseHeadersText)
                        }

                        DetailSectionCard(
                            title: "Response Body",
                            subtitle: task.responseBodyPresentation.bodySummary
                        ) {
                            NetworkResponseBodyContentView(task: task)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 2)
                }
            }
        default:
            detailPane(
                text: responseTabText,
                actions: { responseActions }
            )
        }
        #else
        detailPane(text: responseTabText)
        #endif
    }
}

private extension LogDetailView {
    var inspectorSummaryText: String {
        #if os(macOS) && canImport(Pulse)
        switch selectedPayload {
        case .message:
            return "已选中一条远端普通日志，可查看正文、来源与元数据。"
        case .network:
            return "已选中一条远端网络事务，可查看 Request / Response Header 与 Body。"
        case .none:
            return "在中间 Console 中选择一条日志或网络请求后，这里会显示详细内容。"
        }
        #else
        return "在中间 Console 中选择一条日志或网络请求后，这里会显示详细内容。"
        #endif
    }

    var requestTabText: String {
        #if os(macOS) && canImport(Pulse)
        switch selectedPayload {
        case .message(let message):
            return """
            [\(message.logLevelTitle)] \(message.label)
            Time: \(message.formattedTimestamp)

            \(message.text)
            """
        case .network(let task):
            return """
            \(task.httpMethod ?? "REQUEST") \(task.url ?? "Unknown URL")

            Request Headers
            \(task.requestHeadersText)

            Request Body
            \(task.requestBodyPreviewText)
            """
        case .none:
            return latestPayloadPreview ?? "等待新的远端数据包。收到后，这里会显示最新一条包体预览。"
        }
        #else
        return latestPayloadPreview ?? "等待新的远端数据包。"
        #endif
    }

    var responseTabText: String {
        #if os(macOS) && canImport(Pulse)
        switch selectedPayload {
        case .message(let message):
            return """
            Source
            File: \(message.file)
            Function: \(message.function)
            Line: \(message.line)

            Metadata
            \(message.metadataText.isEmpty ? "No metadata" : message.metadataText)
            """
        case .network(let task):
            return """
            Status: \(task.statusDisplayText)
            Content-Type: \(task.response?.contentType?.type ?? "Unknown")

            Response Headers
            \(task.responseHeadersText)

            Response Body
            \(task.responseBodyText)
            """
        case .none:
            return "网络请求的 Header、状态码和 Response Body 会在你选中中栏条目后显示在这里。"
        }
        #else
        return "网络请求的 Header、状态码和 Response Body 会在你选中中栏条目后显示在这里。"
        #endif
    }

    var metricsTabText: String {
        #if os(macOS) && canImport(Pulse)
        switch selectedPayload {
        case .message(let message):
            return """
            Category: \(message.label)
            Timestamp: \(message.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
            Session: \(message.session.uuidString)
            """
        case .network(let task):
            return """
            Created: \(task.createdAt.formatted(.dateTime.year().month().day().hour().minute().second()))
            Duration: \(task.durationText)
            Request Size: \(task.requestBodySize.byteCountString)
            Response Size: \(task.responseBodySize.byteCountString)
            Redirect Count: \(task.redirectCount)
            Cache: \(task.isFromCache ? "Yes" : "No")
            Error: \(task.errorSummary)
            """
        case .none:
            return """
            当前设备：\(device?.name ?? "Unknown")
            连接状态：\(device?.status.title ?? "Unknown")
            实时速率：\(device?.transferRateText ?? "0 KB/s")
            """
        }
        #else
        return """
        当前设备：\(device?.name ?? "Unknown")
        连接状态：\(device?.status.title ?? "Unknown")
        实时速率：\(device?.transferRateText ?? "0 KB/s")
        """
        #endif
    }

    #if os(macOS) && canImport(Pulse)
    @ViewBuilder
    var responseActions: some View {
        if let responseActionText {
            HStack(spacing: 10) {
                Button {
                    copyResponseText(responseActionText)
                } label: {
                    Label("Copy Response", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                ShareLink(item: responseActionText) {
                    Label("Share Response", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }
        } else {
            EmptyView()
        }
    }

    @ViewBuilder
    func requestActions(for task: NetworkTaskEntity) -> some View {
        HStack(spacing: 10) {
            Button {
                copyResponseText(task.curlCommandText)
            } label: {
                Label("Copy cURL", systemImage: "terminal")
            }
            .buttonStyle(.bordered)

            Spacer(minLength: 12)
        }
    }

    @ViewBuilder
    func responseActions(for task: NetworkTaskEntity) -> some View {
        HStack(spacing: 10) {
            if let copyableText = task.responseBodyPresentation.copyableText {
                Button {
                    copyResponseText(copyableText)
                } label: {
                    Label("Copy Response", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)

                ShareLink(item: copyableText) {
                    Label("Share Response", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
            }

            Button {
                saveResponse(for: task)
            } label: {
                Label("Save Response", systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.bordered)
            .disabled(task.responseExportPayload == nil)

            Spacer(minLength: 12)
        }
    }

    var responseActionText: String? {
        guard case .network(let task) = selectedPayload else {
            return nil
        }
        return task.shareableResponseText
    }

    var selectedPayload: InspectorPayload? {
        guard let selectedConsoleSelection else {
            return nil
        }

        switch selectedConsoleSelection {
        case .message(let objectID):
            return injector.messageEntity(for: objectID).map(InspectorPayload.message)
        case .network(let objectID):
            return injector.networkTaskEntity(for: objectID).map(InspectorPayload.network)
        }
    }

    func copyResponseText(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func saveResponse(for task: NetworkTaskEntity) {
        guard let exportPayload = task.responseExportPayload else {
            saveErrorMessage = "This response does not contain a materialized body that can be saved."
            return
        }

        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportPayload.fileName
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let destinationURL = panel.url else {
            return
        }

        do {
            try exportPayload.data.write(to: destinationURL, options: .atomic)
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }

    func responseOverviewCard(for task: NetworkTaskEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.primaryURLText)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                DetailChip(title: "Status", value: task.statusDisplayText)
                DetailChip(title: "Content-Type", value: task.responseContentTypeValue?.rawValue ?? "Unknown")
                DetailChip(title: "Response Size", value: task.responseBodySize.byteCountString)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }

    func requestOverviewCard(for task: NetworkTaskEntity) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(task.primaryURLText)
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 10) {
                DetailChip(title: "Method", value: task.httpMethod ?? "GET")
                DetailChip(title: "Host", value: task.host ?? "Unknown")
                DetailChip(title: "Request Size", value: task.requestBodySize.byteCountString)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
    #endif
}

#if os(macOS) && canImport(Pulse)
private enum InspectorPayload {
    case message(LoggerMessageEntity)
    case network(NetworkTaskEntity)
}

private struct DetailSectionCard<Content: View>: View {
    let title: String
    let subtitle: String?
    let content: Content

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}

private struct MonospacedDetailText: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(.body, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct NetworkResponseBodyContentView: View {
    let task: NetworkTaskEntity

    var body: some View {
        switch task.responseBodyPresentation {
        case .empty(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        case let .json(_, highlightedText):
            Text(highlightedText)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .text(text):
            MonospacedDetailText(text: text)
        case let .image(preview):
            VStack(alignment: .leading, spacing: 12) {
                Image(nsImage: preview.image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Text("Image preview is cached in memory so reopening this request stays fast.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case let .binary(summary):
            Text(summary)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }
}

#endif

private struct DetailChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.thinMaterial)
        )
    }
}
