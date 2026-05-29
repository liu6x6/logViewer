import SwiftUI

#if os(macOS) && canImport(Pulse) && canImport(PulseUI)
import Pulse
import PulseUI

struct PulseConsoleHostView: View {
    let injector: PulseStoreInjector
    let category: LogCategory

    var body: some View {
        if #available(macOS 15.0, *) {
            ConsoleView(store: injector.store, mode: category.pulseConsoleMode)
                .id(category)
        } else {
            unavailableView("PulseUI ConsoleView requires macOS 15 or later.")
        }
    }

    @ViewBuilder
    private func unavailableView(_ message: String) -> some View {
        ContentUnavailableView(
            "Pulse Console Unavailable",
            systemImage: "exclamationmark.triangle",
            description: Text(message)
        )
    }
}

private extension LogCategory {
    var pulseConsoleMode: ConsoleMode {
        switch self {
        case .messages:
            return .logs
        case .network:
            return .network
        }
    }
}
#elseif os(macOS)
struct PulseConsoleHostView: View {
    let injector: PulseStoreInjector
    let category: LogCategory

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("PulseUI Not Linked")
                .font(.headline)

            Text("`ConsoleView(store:)` will appear here once the Pulse and PulseUI packages are linked to the macOS target.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Current placeholder store: \(injector.storeDescription)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
    }
}
#else
struct PulseConsoleHostView: View {
    let category: LogCategory

    var body: some View {
        EmptyView()
    }
}
#endif
