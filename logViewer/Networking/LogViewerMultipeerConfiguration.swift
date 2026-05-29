import Foundation
@preconcurrency import MultipeerConnectivity

#if os(iOS)
import UIKit
#endif

enum LogViewerPeerRole: String, Sendable {
    case receiver
    case sender
}

enum LogViewerPeerSessionState: String, Sendable {
    case connecting
    case connected
    case notConnected

    init(_ state: MCSessionState) {
        switch state {
        case .connecting:
            self = .connecting
        case .connected:
            self = .connected
        case .notConnected:
            self = .notConnected
        @unknown default:
            self = .notConnected
        }
    }
}

struct LogViewerPeerStateEvent: Identifiable, Hashable, Sendable {
    let id: String
    let displayName: String
    let role: LogViewerPeerRole
    let state: LogViewerPeerSessionState
    let occurredAt: Date
}

struct LogViewerReceivedPacket: Identifiable, Hashable, Sendable {
    let id: String
    let peerID: String
    let displayName: String
    let data: Data
    let receivedAt: Date

    init(peerID: String, displayName: String, data: Data, receivedAt: Date = .now) {
        self.id = UUID().uuidString
        self.peerID = peerID
        self.displayName = displayName
        self.data = data
        self.receivedAt = receivedAt
    }

    nonisolated var payloadPreview: String {
        data.logViewerPreview()
    }
}

enum LogViewerMultipeerConfiguration {
    nonisolated static let serviceType = "logviewer-pipe"
    nonisolated static let bonjourService = "_\(serviceType)._tcp"
    nonisolated static let invitationTimeout: TimeInterval = 12

    nonisolated static let roleKey = "role"
    nonisolated static let platformKey = "platform"

    nonisolated static func makePeerID(displayName: String = defaultDisplayName) -> MCPeerID {
        MCPeerID(displayName: sanitizedDisplayName(displayName))
    }

    nonisolated static func discoveryInfo(for role: LogViewerPeerRole) -> [String: String] {
        [
            roleKey: role.rawValue,
            platformKey: currentPlatform
        ]
    }

    nonisolated static let defaultDisplayName: String = {
        #if os(iOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac Receiver"
        #else
        return "logViewer"
        #endif
    }()

    private nonisolated static let currentPlatform: String = {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }()

    private nonisolated static func sanitizedDisplayName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = trimmed.isEmpty ? "logViewer" : trimmed

        // MCPeerID display names are limited to 63 UTF-8 bytes.
        return String(fallback.prefix(63))
    }
}

enum LogViewerPacketPrinter {
    nonisolated static func printPacket(_ packet: LogViewerReceivedPacket) {
        let threadLabel = Thread.isMainThread ? "main" : "background"
        print("[logViewer][RX][\(threadLabel)] peer=\(packet.displayName) bytes=\(packet.data.count)")

        do {
            let decodedPacket = try LogPacketDecoder().decodeEnvelopeAndPayload(from: packet.data)

            switch decodedPacket {
            case .message(let envelope, let payload):
                print("[logViewer][Message] ts=\(envelope.timestamp) level=\(payload.level.title) category=\(payload.category)")
                print(payload.message)

            case .network(let envelope, let payload):
                print("[logViewer][Network] ts=\(envelope.timestamp) method=\(payload.method) status=\(payload.statusCode)")
                print("URL: \(payload.url)")
                print("Request headers: \(payload.requestHeaders.count), Response headers: \(payload.responseHeaders.count)")
                print("Response body: \(payload.responseBody.logViewerPreview())")
            }
        } catch {
            print("[logViewer][RX] undecoded payload: \(error.localizedDescription)")
            print(packet.payloadPreview)
        }
    }
}
