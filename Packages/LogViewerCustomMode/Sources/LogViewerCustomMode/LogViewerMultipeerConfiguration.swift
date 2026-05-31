import Foundation
@preconcurrency import MultipeerConnectivity

#if os(iOS)
import UIKit
#endif

public enum LogViewerPeerRole: String, Sendable {
    case receiver
    case sender
}

public enum LogViewerPeerSessionState: String, Sendable {
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

public struct LogViewerPeerStateEvent: Identifiable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let role: LogViewerPeerRole
    public let state: LogViewerPeerSessionState
    public let occurredAt: Date
}

public struct LogViewerReceivedPacket: Identifiable, Hashable, Sendable {
    public let id: String
    public let peerID: String
    public let displayName: String
    public let data: Data
    public let receivedAt: Date

    init(peerID: String, displayName: String, data: Data, receivedAt: Date = .now) {
        self.id = UUID().uuidString
        self.peerID = peerID
        self.displayName = displayName
        self.data = data
        self.receivedAt = receivedAt
    }

    public nonisolated var payloadPreview: String {
        data.logViewerPreview()
    }
}

public enum LogViewerMultipeerConfiguration {
    public nonisolated static let serviceType = "logviewer-pipe"
    public nonisolated static let bonjourService = "_\(serviceType)._tcp"
    public nonisolated static let invitationTimeout: TimeInterval = 12

    public nonisolated static let roleKey = "role"
    public nonisolated static let platformKey = "platform"

    public nonisolated static func makePeerID(displayName: String) -> MCPeerID {
        MCPeerID(displayName: sanitizedDisplayName(displayName))
    }

    public nonisolated static func discoveryInfo(for role: LogViewerPeerRole) -> [String: String] {
        [
            roleKey: role.rawValue,
            platformKey: currentPlatform
        ]
    }

    @MainActor
    public static var defaultDisplayName: String {
        #if os(iOS)
        UIDevice.current.name
        #elseif os(macOS)
        Host.current().localizedName ?? "Mac Receiver"
        #else
        "logViewer"
        #endif
    }

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
