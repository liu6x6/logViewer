import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager
    @ObservedObject var actionCoordinator: NetworkRequestActionCoordinator

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedDeviceID: DeviceModel.ID?
    @State private var selectedCategory: LogCategory = .network
    @State private var selectedConsoleSelection: PulseConsoleSelection?
    @State private var isInspectorCollapsed = false

    private var selectedDevice: DeviceModel? {
        connectionManager.devices.first { $0.id == selectedDeviceID }
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            DeviceSidebarView(selectedDeviceID: $selectedDeviceID)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 360)
        } content: {
            LogPanelView(
                device: selectedDevice,
                selectedCategory: $selectedCategory,
                selectedConsoleSelection: $selectedConsoleSelection,
                actionCoordinator: actionCoordinator
            )
            .navigationSplitViewColumnWidth(min: 420, ideal: 620)
        } detail: {
            if isInspectorCollapsed {
                Color.clear
                    .navigationSplitViewColumnWidth(min: 0, ideal: 0, max: 0)
            } else {
                LogDetailView(
                    device: selectedDevice,
                    latestPayloadPreview: connectionManager.latestReceivedPayload,
                    selectedConsoleSelection: selectedConsoleSelection,
                    injector: connectionManager.pulseInjector,
                    actionCoordinator: actionCoordinator
                )
                .navigationSplitViewColumnWidth(min: 420, ideal: 540, max: 640)
            }
        }
        .navigationSplitViewStyle(.balanced)
        .animation(.easeInOut(duration: 0.22), value: isInspectorCollapsed)
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

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isInspectorCollapsed.toggle()
                } label: {
                    Label(
                        isInspectorCollapsed ? "Show Inspector" : "Hide Inspector",
                        systemImage: "sidebar.trailing"
                    )
                }
                .help(isInspectorCollapsed ? "展开右侧属性页" : "折叠右侧属性页")
            }
        }
        .onAppear {
            if selectedDeviceID == nil {
                selectedDeviceID = connectionManager.devices.first?.id
            }
            actionCoordinator.selectedConsoleSelection = selectedConsoleSelection
        }
        .onChange(of: selectedConsoleSelection) { _, newValue in
            actionCoordinator.selectedConsoleSelection = newValue
        }
        .onChange(of: selectedDeviceID) { _, _ in
            selectedConsoleSelection = nil
        }
    }
}
