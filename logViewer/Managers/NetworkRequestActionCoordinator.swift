import SwiftUI
import Combine

#if os(macOS) && canImport(Pulse)
import AppKit
import Pulse

@MainActor
final class NetworkRequestActionCoordinator: ObservableObject {
    weak var injector: PulseStoreInjector?
    @Published var selectedConsoleSelection: PulseConsoleSelection?
    @Published private(set) var isSendingAgain = false

    var selectedNetworkTask: NetworkTaskEntity? {
        guard
            let injector,
            case .network(let objectID) = selectedConsoleSelection
        else {
            return nil
        }
        return injector.networkTaskEntity(for: objectID)
    }

    var hasSelectedNetworkTask: Bool {
        selectedNetworkTask != nil
    }

    func configure(injector: PulseStoreInjector) {
        self.injector = injector
    }

    func canCopy(_ action: NetworkRequestCopyAction) -> Bool {
        guard let task = selectedNetworkTask else {
            return false
        }
        return action.text(from: task) != nil
    }

    func copy(_ action: NetworkRequestCopyAction) {
        guard
            let task = selectedNetworkTask,
            let text = action.text(from: task)
        else {
            NSSound.beep()
            return
        }
        copy(text)
    }

    func copy(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    func sendAgain() {
        guard let task = selectedNetworkTask else {
            NSSound.beep()
            return
        }
        sendAgain(task)
    }

    func sendAgain(_ task: NetworkTaskEntity) {
        guard !isSendingAgain else {
            return
        }

        guard let injector else {
            NSSound.beep()
            return
        }

        isSendingAgain = true

        Task { @MainActor in
            defer {
                isSendingAgain = false
            }

            do {
                try await injector.sendAgain(for: task)
            } catch {
                presentError(title: "Failed to Send Request", message: error.localizedDescription)
            }
        }
    }

    private func presentError(title: String, message: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

struct RequestCommands: Commands {
    @ObservedObject var actionCoordinator: NetworkRequestActionCoordinator

    var body: some Commands {
        CommandMenu("Request") {
            requestCopyButton(.url, shortcut: "u")
            requestCopyButton(.queryParameters, shortcut: "p")
            requestCopyButton(.headers, shortcut: "h")
            requestCopyButton(.body, shortcut: "b")
            requestCopyButton(.cURL, shortcut: "c")

            Divider()

            requestCopyButton(.queryParametersJSON)
            requestCopyButton(.headersJSON)
            requestCopyButton(.bodyPrettyJSON)
            requestCopyButton(.requestSummary)

            Divider()

            Button {
                actionCoordinator.sendAgain()
            } label: {
                Label(
                    actionCoordinator.isSendingAgain ? "Sending..." : "Send Again",
                    systemImage: actionCoordinator.isSendingAgain ? "hourglass" : "paperplane"
                )
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(!actionCoordinator.hasSelectedNetworkTask || actionCoordinator.isSendingAgain)
        }
    }

    @ViewBuilder
    private func requestCopyButton(_ action: NetworkRequestCopyAction, shortcut: KeyEquivalent? = nil) -> some View {
        Button {
            actionCoordinator.copy(action)
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .applyShortcut(shortcut)
        .disabled(!actionCoordinator.canCopy(action))
    }
}

private extension View {
    @ViewBuilder
    func applyShortcut(_ key: KeyEquivalent?) -> some View {
        if let key {
            keyboardShortcut(key, modifiers: [.command, .shift])
        } else {
            self
        }
    }
}
#endif
