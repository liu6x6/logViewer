import SwiftUI

private enum DetailTab: String, CaseIterable, Hashable {
    case request = "Request"
    case response = "Response"
    case metrics = "Metrics"
}

struct LogDetailView: View {
    let device: DeviceModel?
    let latestPayloadPreview: String?

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

                Text("右侧面板继续保留为自定义占位区；完整的日志与网络响应解析已经交给中栏的 Pulse Console。")
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    DetailChip(title: "Device", value: device?.name ?? "Unknown")
                    DetailChip(title: "Status", value: device?.status.title ?? "Unknown")
                    DetailChip(title: "Rate", value: device?.transferRateText ?? "0 KB/s")
                }
            }

            TabView(selection: $selectedTab) {
                detailPane(text: latestPayloadPreview ?? "等待新的远端数据包。收到后，这里会显示最新一条包体预览。")
                    .tabItem { Text(DetailTab.request.rawValue) }
                    .tag(DetailTab.request)

                detailPane(text: "网络请求的 Header、状态码和 Response Body 已经直接写入 Pulse Store。请在中间的 Pulse Console 里选择对应请求查看完整解析结果。")
                    .tabItem { Text(DetailTab.response.rawValue) }
                    .tag(DetailTab.response)

                detailPane(text: "当前设备：\(device?.name ?? "Unknown")\n连接状态：\(device?.status.title ?? "Unknown")\n实时速率：\(device?.transferRateText ?? "0 KB/s")")
                    .tabItem { Text(DetailTab.metrics.rawValue) }
                    .tag(DetailTab.metrics)
            }
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
