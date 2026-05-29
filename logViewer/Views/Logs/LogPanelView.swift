import SwiftUI

struct LogPanelView: View {
    @EnvironmentObject private var connectionManager: ConnectionManager

    let device: DeviceModel?
    @Binding var selectedCategory: LogCategory
    @Binding var selectedConsoleSelection: PulseConsoleSelection?
    @State private var isShowingClearConfirmation = false
    @State private var isShowingNetworkBlacklist = false

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
        #if os(macOS)
        .alert("Clear all records?", isPresented: $isShowingClearConfirmation) {
            Button("Clear", role: .destructive) {
                selectedConsoleSelection = nil
                connectionManager.clearStoredRecords()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes all stored messages, network requests, and device connection history from the current session.")
        }
        .sheet(isPresented: $isShowingNetworkBlacklist) {
            NetworkBlacklistSheet(blocklist: connectionManager.networkBlocklist)
        }
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
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

            Spacer(minLength: 16)

            #if os(macOS)
            HStack(spacing: 10) {
                if selectedCategory == .network {
                    Button {
                        isShowingNetworkBlacklist = true
                    } label: {
                        Label(blacklistButtonTitle, systemImage: "shield.lefthalf.filled")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    isShowingClearConfirmation = true
                } label: {
                    Label("Clear Records", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            #endif
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
    }

    #if os(macOS)
    private var blacklistButtonTitle: String {
        let totalCount = connectionManager.networkBlocklist.snapshot.totalCount
        return totalCount == 0 ? "Blacklist" : "Blacklist (\(totalCount))"
    }
    #endif

    @ViewBuilder
    private func console(for category: LogCategory) -> some View {
        #if os(macOS)
        PulseConsoleHostView(
            injector: connectionManager.pulseInjector,
            category: category,
            selection: $selectedConsoleSelection
        )
        #else
        Text("Pulse Console is only available on macOS in this project.")
            .font(.caption)
            .foregroundStyle(.secondary)
        #endif
    }
}
