#if os(iOS)
import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

enum IOSLogSenderError: LocalizedError {
    case noConnectedReceiver

    var errorDescription: String? {
        switch self {
        case .noConnectedReceiver:
            return "No connected Mac receiver is available."
        }
    }
}

/// Advertises the iPhone on the local Wi-Fi network and accepts Mac connection invitations automatically.
@MainActor
final class IOSLogSender: NSObject, ObservableObject {
    @Published private(set) var connectedPeerDisplayNames: [String] = []
    @Published private(set) var isAdvertising = false

    private let localPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let packetEncoder: LogPacketEncoder

    init(displayName: String = LogViewerMultipeerConfiguration.defaultDisplayName) {
        let localPeerID = LogViewerMultipeerConfiguration.makePeerID(displayName: displayName)

        self.localPeerID = localPeerID
        self.session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.packetEncoder = LogPacketEncoder()
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: localPeerID,
            discoveryInfo: LogViewerMultipeerConfiguration.discoveryInfo(for: .sender),
            serviceType: LogViewerMultipeerConfiguration.serviceType
        )

        super.init()

        session.delegate = self
        advertiser.delegate = self
        startAdvertising()
    }

    func startAdvertising() {
        guard !isAdvertising else {
            return
        }

        advertiser.startAdvertisingPeer()
        isAdvertising = true
    }

    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        isAdvertising = false
    }

    /// Public sending entry used later by the log streaming pipeline.
    func sendPacket(data: Data) throws {
        guard !session.connectedPeers.isEmpty else {
            throw IOSLogSenderError.noConnectedReceiver
        }

        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    func sendLogMessage(
        message: String,
        level: LogMessageLevel,
        category: String,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        let payload = LogMessagePayload(message: message, level: level, category: category)
        let packetData = try packetEncoder.encodeLogMessage(payload, timestamp: timestamp)
        try sendPacket(data: packetData)
    }

    func sendNetworkSummary(
        url: URL,
        method: String,
        requestHeaders: [String: String],
        responseHeaders: [String: String],
        statusCode: Int,
        responseBody: Data,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws {
        let payload = LogNetworkPayload(
            url: url,
            method: method,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            statusCode: statusCode,
            responseBody: responseBody
        )
        let packetData = try packetEncoder.encodeNetworkSummary(payload, timestamp: timestamp)
        try sendPacket(data: packetData)
    }
}

extension IOSLogSender: MCNearbyServiceAdvertiserDelegate {
    func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        invitationHandler(true, session)
    }

    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: any Error) {
        isAdvertising = false
        print("[logViewer][Advertiser] failed to start advertising: \(error.localizedDescription)")
    }
}

extension IOSLogSender: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        connectedPeerDisplayNames = session.connectedPeers
            .map(\.displayName)
            .sorted()
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // The iPhone sender does not currently expect inbound packets.
    }

    func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {
        // The current transport only uses Data packets.
    }

    func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {
        // Resources are not used yet, but the delegate requirement must still be satisfied.
    }

    func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: (any Error)?
    ) {
        if let error {
            print("[logViewer][Sender] resource receive failed: \(error.localizedDescription)")
        }
    }

    func session(
        _ session: MCSession,
        didReceiveCertificate certificate: [Any]?,
        fromPeer peerID: MCPeerID,
        certificateHandler: @escaping (Bool) -> Void
    ) {
        certificateHandler(true)
    }
}
#endif
