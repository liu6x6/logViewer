import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedDeviceID: DeviceModel.ID?
    @State private var selectedCategory: LogCategory = .messages

    private var selectedDevice: DeviceModel? {
        connectionManager.devices.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeviceSidebarView(selectedDeviceID: $selectedDeviceID)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } content: {
            LogPanelView(device: selectedDevice, selectedCategory: $selectedCategory)
                .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            LogDetailView(
                device: selectedDevice,
                latestPayloadPreview: connectionManager.latestReceivedPayload
            )
                .navigationSplitViewColumnWidth(min: 420, ideal: 540)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 2) {
                    Text(selectedDevice?.name ?? "logViewer")
                        .font(.headline)
                    Text(selectedDevice?.status.title ?? "等待设备接入")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear {
            if selectedDeviceID == nil {
                selectedDeviceID = connectionManager.devices.first?.id
            }
        }
    }
}
