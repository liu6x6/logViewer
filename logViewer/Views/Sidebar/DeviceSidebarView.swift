import SwiftUI

struct DeviceSidebarView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @Binding var selectedDeviceID: DeviceModel.ID?

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                Divider()

                List(selection: $selectedDeviceID) {
                    ForEach(connectionManager.devices) { device in
                        DeviceRowView(device: device)
                            .tag(device.id)
                    }
                }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Devices")
                    .font(.title3.weight(.semibold))
                Text("实时连接的 iOS / Android 设备与历史会话")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(connectionManager.devices.filter { $0.status == .connected }.count) Online")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(16)
    }
}

private struct DeviceRowView: View {
    let device: DeviceModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: device.platform.symbolName)
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name)
                        .font(.headline)
                        .lineLimit(2)

                    HStack(spacing: 8) {
                        Text(device.platform.title)
                            .foregroundStyle(.secondary)

                        Label(device.status.title, systemImage: device.status.symbolName)
                            .labelStyle(.titleAndIcon)
                            .foregroundStyle(device.status.color)

                        Text(device.transferRateText)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(device.historySummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                ForEach(device.recentHistory) { record in
                    Text("• \(record.note) · \(record.timestamp.formatted(.dateTime.hour().minute()))")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 6)
    }
}
