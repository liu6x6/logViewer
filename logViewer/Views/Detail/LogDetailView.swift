import SwiftUI
#if os(macOS) && canImport(Pulse)
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

    var body: some View {
        content
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
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
                detailPane(text: requestTabText)
                    .tabItem { Text(DetailTab.request.rawValue) }
                    .tag(DetailTab.request)

                detailPane(text: responseTabText)
                    .tabItem { Text(DetailTab.response.rawValue) }
                    .tag(DetailTab.response)

                detailPane(text: metricsTabText)
                    .tabItem { Text(DetailTab.metrics.rawValue) }
                    .tag(DetailTab.metrics)
            }
        }
        .onChange(of: selectedConsoleSelection) {
            selectedTab = .request
        }
    }

    private func detailPane(text: String) -> some View {
        ScrollView {
            Text(text)
                .font(.system(.body, design: .monospaced))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(.thinMaterial)
                )
        }
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
            \(task.responseBodyPreviewText)
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
    #endif
}

#if os(macOS) && canImport(Pulse)
private enum InspectorPayload {
    case message(LoggerMessageEntity)
    case network(NetworkTaskEntity)
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
