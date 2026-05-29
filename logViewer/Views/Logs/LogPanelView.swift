import SwiftUI

struct LogPanelView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager

    let device: DeviceModel?
    @Binding var selectedCategory: LogCategory

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            TabView(selection: $selectedCategory) {
                console(for: .messages)
                    .tabItem {
                        Label("Messages", systemImage: LogCategory.messages.symbolName)
                    }
                    .tag(LogCategory.messages)

                console(for: .network)
                    .tabItem {
                        Label("Network", systemImage: LogCategory.network.symbolName)
                    }
                    .tag(LogCategory.network)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(device?.name ?? "Select a device")
                .font(.title3.weight(.semibold))

            #if os(macOS)
            Text("Pulse live store · \(connectionManager.pulseInjector.storeDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
            #else
            Text("日志控制台将显示来自 iOS 端的实时 Messages 与 Network 流。")
                .font(.caption)
                .foregroundStyle(.secondary)
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    @ViewBuilder
    private func console(for category: LogCategory) -> some View {
        #if os(macOS)
        PulseConsoleHostView(injector: connectionManager.pulseInjector, category: category)
        #else
        Text("Pulse Console is only available on macOS in this project.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}
