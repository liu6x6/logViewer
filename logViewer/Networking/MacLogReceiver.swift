#if os(macOS)
import Combine
import Foundation
@preconcurrency import MultipeerConnectivity

/// Auto-discovers nearby iPhone senders and forwards connection/data events to the UI state layer.
@MainActor
final class MacLogReceiver: NSObject, ObservableObject {
    @Published private(set) var connectedPeerDisplayNames: [String] = []

    var onPeerStateChange: ((LogViewerPeerStateEvent) -> Void)?
    var onPacketReceived: ((LogViewerReceivedPacket) -> Void)?

    private let localPeerID: MCPeerID
    private let session: MCSession
    private let browser: MCNearbyServiceBrowser

    private var invitedPeerIDs: Set<String> = []

    init(displayName: String = LogViewerMultipeerConfiguration.defaultDisplayName) {
        let localPeerID = LogViewerMultipeerConfiguration.makePeerID(displayName: displayName)

        self.localPeerID = localPeerID
        self.session = MCSession(
            peer: localPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.browser = MCNearbyServiceBrowser(peer: localPeerID, serviceType: LogViewerMultipeerConfiguration.serviceType)

        super.init()

        session.delegate = self
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func stop() {
        browser.stopBrowsingForPeers()
        session.disconnect()
        invitedPeerIDs.removeAll()
        connectedPeerDisplayNames = []
    }

    private func inviteIfNeeded(peerID: MCPeerID, discoveryInfo: [String: String]?) {
        guard discoveryInfo?[LogViewerMultipeerConfiguration.roleKey] == LogViewerPeerRole.sender.rawValue else {
            return
        }

        guard !session.connectedPeers.contains(peerID) else {
            return
        }

        let peerKey = peerID.displayName

        guard invitedPeerIDs.insert(peerKey).inserted else {
            return
        }

        browser.invitePeer(
            peerID,
            to: session,
            withContext: nil,
            timeout: LogViewerMultipeerConfiguration.invitationTimeout
        )
    }

    private func publishConnectionState(for peerID: MCPeerID, state: MCSessionState) {
        let mappedState = LogViewerPeerSessionState(state)
        let peerKey = peerID.displayName

        if mappedState != .connecting {
            invitedPeerIDs.remove(peerKey)
        }

        connectedPeerDisplayNames = session.connectedPeers
            .map(\.displayName)
            .sorted()

        onPeerStateChange?(
            LogViewerPeerStateEvent(
                id: peerKey,
                displayName: peerID.displayName,
                role: .sender,
                state: mappedState,
                occurredAt: .now
            )
        )
    }
}

extension MacLogReceiver: MCNearbyServiceBrowserDelegate {
    func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        inviteIfNeeded(peerID: peerID, discoveryInfo: info)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        invitedPeerIDs.remove(peerID.displayName)
    }

    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: any Error) {
        print("[logViewer][Browser] failed to start browsing: \(error.localizedDescription)")
    }
}

extension MacLogReceiver: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        publishConnectionState(for: peerID, state: state)
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        let packet = LogViewerReceivedPacket(
            peerID: peerID.displayName,
            displayName: peerID.displayName,
            data: data
        )

        Task.detached(priority: .utility) {
            LogViewerPacketPrinter.printPacket(packet)
        }

        onPacketReceived?(packet)
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
            print("[logViewer][Receiver] resource receive failed: \(error.localizedDescription)")
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
