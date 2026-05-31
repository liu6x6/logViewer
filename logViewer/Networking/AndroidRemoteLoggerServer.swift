#if os(macOS)
import Foundation
import Network

struct AndroidRemoteLoggerPeerStateEvent: Identifiable, Sendable {
    enum State: Sendable {
        case connected
        case notConnected
    }

    let id: String
    let displayName: String
    let appName: String
    let state: State
    let occurredAt: Date
}

struct AndroidRemoteLoggerReceivedEvent: Identifiable, Sendable {
    let id: String
    let peerID: String
    let displayName: String
    let appName: String
    let event: AndroidRemoteLoggerEvent
    let byteCount: Int
    let receivedAt: Date

    var payloadPreview: String {
        switch event {
        case .message(let payload):
            return payload.message
        case .networkCompleted(let payload):
            let status = payload.statusCode.map(String.init) ?? (payload.error == nil ? "done" : "failed")
            return "\(payload.method) \(payload.url) · \(status)"
        }
    }
}

@MainActor
final class AndroidRemoteLoggerServer: NSObject {
    nonisolated static let defaultPort: UInt16 = 52_888

    var onPeerStateChange: ((AndroidRemoteLoggerPeerStateEvent) -> Void)?
    var onEventReceived: ((AndroidRemoteLoggerReceivedEvent) -> Void)?

    private var listener: NWListener?
    private var bonjourService: NetService?
    private var activeConnections: [UUID: AndroidRemoteLoggerClientConnection] = [:]
    private let listenerQueue = DispatchQueue(label: "logviewer.android.remote-listener")
    private let serviceName: String
    private let port: UInt16

    init(
        serviceName: String = AndroidRemoteLoggerServer.makeDefaultServiceName(),
        port: UInt16 = AndroidRemoteLoggerServer.defaultPort
    ) {
        self.serviceName = serviceName
        self.port = port
        super.init()
        start()
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil
        bonjourService?.stop()
        bonjourService = nil

        activeConnections.values.forEach { $0.stop() }
        activeConnections.removeAll()
    }

    private func start() {
        do {
            let listener = try NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: port)!)
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    print("[logViewer][AndroidRemoteLogger] listening on port \(self.port)")
                    Task { @MainActor [weak self] in
                        self?.startBonjourAdvertising()
                    }
                case .waiting(let error):
                    print("[logViewer][AndroidRemoteLogger] listener waiting: \(error.localizedDescription)")
                case .failed(let error):
                    print("[logViewer][AndroidRemoteLogger] listener failed: \(error.localizedDescription)")
                case .cancelled:
                    print("[logViewer][AndroidRemoteLogger] listener cancelled")
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in
                guard let self else {
                    return
                }
                Task { @MainActor [self, connection] in
                    self.registerConnection(connection)
                }
            }
            listener.start(queue: listenerQueue)
            self.listener = listener
        } catch {
            print("[logViewer][AndroidRemoteLogger] failed to start listener: \(error.localizedDescription)")
        }
    }

    private func registerConnection(_ connection: NWConnection) {
        let clientConnection = AndroidRemoteLoggerClientConnection(connection: connection)

        clientConnection.onHandshake = { [weak self] identity in
            Task { @MainActor in
                self?.handleHandshake(identity, for: clientConnection)
            }
        }

        clientConnection.onEventReceived = { [weak self] identity, event, byteCount in
            Task { @MainActor in
                self?.handleEvent(event, from: identity, byteCount: byteCount)
            }
        }

        clientConnection.onConnectionClosed = { [weak self] identity in
            Task { @MainActor in
                self?.activeConnections[clientConnection.id] = nil
                self?.handleClosedConnection(identity)
            }
        }

        clientConnection.onProtocolError = { error in
            print("[logViewer][AndroidRemoteLogger] protocol error: \(error.localizedDescription)")
        }

        activeConnections[clientConnection.id] = clientConnection
        clientConnection.start()
    }

    private func handleHandshake(
        _ identity: AndroidRemoteLoggerClientIdentity,
        for connection: AndroidRemoteLoggerClientConnection
    ) {
        activeConnections[connection.id] = connection

        onPeerStateChange?(
            AndroidRemoteLoggerPeerStateEvent(
                id: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                state: .connected,
                occurredAt: .now
            )
        )
    }

    private func handleEvent(
        _ event: AndroidRemoteLoggerEvent,
        from identity: AndroidRemoteLoggerClientIdentity,
        byteCount: Int
    ) {
        onEventReceived?(
            AndroidRemoteLoggerReceivedEvent(
                id: UUID().uuidString,
                peerID: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                event: event,
                byteCount: byteCount,
                receivedAt: .now
            )
        )
    }

    private func handleClosedConnection(_ identity: AndroidRemoteLoggerClientIdentity?) {
        guard let identity else {
            return
        }

        onPeerStateChange?(
            AndroidRemoteLoggerPeerStateEvent(
                id: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                state: .notConnected,
                occurredAt: .now
            )
        )
    }

    private func makeTXTRecord() -> Data? {
        let fields = [
            "role": "viewer-server",
            "protocol": "1",
            "accepts": "android,ios",
            "name": serviceName
        ]
        return NetService.data(fromTXTRecord: fields.mapValues { Data($0.utf8) })
    }

    private func startBonjourAdvertising() {
        guard bonjourService == nil else {
            return
        }

        let service = NetService(
            domain: "local.",
            type: AndroidRemoteLoggerProtocol.viewerNetServiceType,
            name: serviceName,
            port: Int32(port)
        )
        service.setTXTRecord(makeTXTRecord())
        service.publish()
        bonjourService = service
    }

    nonisolated private static func makeDefaultServiceName() -> String {
        if let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String, !appName.isEmpty {
            return appName
        }
        return Host.current().localizedName ?? "logViewer"
    }
}

@MainActor
final class AndroidRemoteLoggerBrowser {
    var onPeerStateChange: ((AndroidRemoteLoggerPeerStateEvent) -> Void)?
    var onEventReceived: ((AndroidRemoteLoggerReceivedEvent) -> Void)?

    private var browser: NWBrowser?
    private var discoveredResults: [String: NWBrowser.Result] = [:]
    private var activeConnections: [String: AndroidRemoteLoggerClientConnection] = [:]
    private var reconnectTasks: [String: Task<Void, Never>] = [:]
    private let browseQueue = DispatchQueue(label: "logviewer.android.remote-browser")

    init() {
        start()
    }

    func stop() {
        browser?.cancel()
        browser = nil

        reconnectTasks.values.forEach { $0.cancel() }
        reconnectTasks.removeAll()

        activeConnections.values.forEach { $0.stop() }
        activeConnections.removeAll()
        discoveredResults.removeAll()
    }

    private func start() {
        let browser = NWBrowser(
            for: .bonjour(type: AndroidRemoteLoggerProtocol.deviceNetServiceType, domain: nil),
            using: .tcp
        )

        browser.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("[logViewer][AndroidRemoteLoggerBrowser] browsing for Android devices")
            case .failed(let error):
                print("[logViewer][AndroidRemoteLoggerBrowser] browser failed: \(error.localizedDescription)")
            default:
                break
            }
        }

        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor [weak self] in
                self?.syncResults(results)
            }
        }

        browser.start(queue: browseQueue)
        self.browser = browser
    }

    private func syncResults(_ results: Set<NWBrowser.Result>) {
        let mappedResults = Dictionary(uniqueKeysWithValues: results.map { (key(for: $0), $0) })
        let removedKeys = Set(discoveredResults.keys).subtracting(mappedResults.keys)

        discoveredResults = mappedResults

        for key in removedKeys {
            reconnectTasks[key]?.cancel()
            reconnectTasks[key] = nil
            activeConnections[key]?.stop()
            activeConnections[key] = nil
        }

        for (key, result) in mappedResults where activeConnections[key] == nil {
            connect(to: result, key: key)
        }
    }

    private func connect(to result: NWBrowser.Result, key: String) {
        reconnectTasks[key]?.cancel()
        reconnectTasks[key] = nil

        let connection = NWConnection(to: result.endpoint, using: .tcp)
        let clientConnection = AndroidRemoteLoggerClientConnection(connection: connection)

        clientConnection.onHandshake = { [weak self] identity in
            Task { @MainActor in
                self?.handleHandshake(identity, key: key, connection: clientConnection)
            }
        }

        clientConnection.onEventReceived = { [weak self] identity, event, byteCount in
            Task { @MainActor in
                self?.handleEvent(event, from: identity, byteCount: byteCount)
            }
        }

        clientConnection.onConnectionClosed = { [weak self] identity in
            Task { @MainActor in
                self?.activeConnections[key] = nil
                self?.handleClosedConnection(identity)
                self?.scheduleReconnect(for: key)
            }
        }

        clientConnection.onProtocolError = { error in
            print("[logViewer][AndroidRemoteLoggerBrowser] protocol error: \(error.localizedDescription)")
        }

        activeConnections[key] = clientConnection
        clientConnection.start()
    }

    private func handleHandshake(
        _ identity: AndroidRemoteLoggerClientIdentity,
        key: String,
        connection: AndroidRemoteLoggerClientConnection
    ) {
        activeConnections[key] = connection

        onPeerStateChange?(
            AndroidRemoteLoggerPeerStateEvent(
                id: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                state: .connected,
                occurredAt: .now
            )
        )
    }

    private func handleEvent(
        _ event: AndroidRemoteLoggerEvent,
        from identity: AndroidRemoteLoggerClientIdentity,
        byteCount: Int
    ) {
        onEventReceived?(
            AndroidRemoteLoggerReceivedEvent(
                id: UUID().uuidString,
                peerID: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                event: event,
                byteCount: byteCount,
                receivedAt: .now
            )
        )
    }

    private func handleClosedConnection(_ identity: AndroidRemoteLoggerClientIdentity?) {
        guard let identity else {
            return
        }

        onPeerStateChange?(
            AndroidRemoteLoggerPeerStateEvent(
                id: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                state: .notConnected,
                occurredAt: .now
            )
        )
    }

    private func scheduleReconnect(for key: String) {
        guard discoveredResults[key] != nil else {
            return
        }

        reconnectTasks[key]?.cancel()
        reconnectTasks[key] = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, let result = await MainActor.run(body: { self.discoveredResults[key] }) else {
                return
            }
            await MainActor.run {
                guard self.activeConnections[key] == nil else {
                    return
                }
                self.connect(to: result, key: key)
            }
        }
    }

    private func key(for result: NWBrowser.Result) -> String {
        result.endpoint.debugDescription
    }
}

struct AndroidRemoteLoggerClientIdentity: Sendable {
    let deviceID: String
    let displayName: String
    let appName: String
    let appVersion: String
    let osVersion: String

    var stableIdentifier: String {
        "\(deviceID)|\(appName)"
    }

    init(_ hello: AndroidRemoteLoggerHelloPayload) {
        self.deviceID = hello.deviceId
        self.displayName = hello.deviceName
        self.appName = hello.appId
        self.appVersion = hello.appVersion
        self.osVersion = hello.osVersion
    }
}

final class AndroidRemoteLoggerClientConnection {
    let id = UUID()

    var onHandshake: ((AndroidRemoteLoggerClientIdentity) -> Void)?
    var onEventReceived: ((AndroidRemoteLoggerClientIdentity, AndroidRemoteLoggerEvent, Int) -> Void)?
    var onConnectionClosed: ((AndroidRemoteLoggerClientIdentity?) -> Void)?
    var onProtocolError: ((Error) -> Void)?

    private(set) var identity: AndroidRemoteLoggerClientIdentity?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "logviewer.android.remote-client")
    private var buffer = Data()
    private var hasClosed = false

    init(connection: NWConnection) {
        self.connection = connection
    }

    func start() {
        connection.stateUpdateHandler = { [weak self] state in
            self?.handleState(state)
        }
        receive()
        connection.start(queue: queue)
    }

    func stop() {
        connection.cancel()
        closeIfNeeded()
    }

    private func handleState(_ state: NWConnection.State) {
        switch state {
        case .failed(let error):
            onProtocolError?(error)
            closeIfNeeded()
        case .cancelled:
            closeIfNeeded()
        default:
            break
        }
    }

    private func receive() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_535) { [weak self] data, _, isComplete, error in
            guard let self else {
                return
            }

            if let error {
                self.onProtocolError?(error)
                self.closeIfNeeded()
                return
            }

            if let data, !data.isEmpty {
                self.process(data)
            }

            if isComplete {
                self.closeIfNeeded()
            } else {
                self.receive()
            }
        }
    }

    private func process(_ incomingData: Data) {
        buffer.append(incomingData)

        while let lineRange = buffer.firstRange(of: Data([0x0A])) {
            let lineData = buffer[..<lineRange.lowerBound]
            buffer.removeSubrange(..<lineRange.upperBound)

            guard !lineData.isEmpty else {
                continue
            }

            handleLine(Data(lineData), wireSize: lineData.count + 1)
        }
    }

    private func handleLine(_ data: Data, wireSize: Int) {
        do {
            let envelope = try AndroidRemoteLoggerProtocol.decodeEnvelope(from: data)

            switch envelope.type {
            case "hello":
                guard let hello = envelope.hello else {
                    throw AndroidRemoteLoggerProtocolError.missingPayload(envelope.type)
                }
                let identity = AndroidRemoteLoggerClientIdentity(hello)
                self.identity = identity
                onHandshake?(identity)
            default:
                guard let identity else {
                    return
                }
                let event = try AndroidRemoteLoggerProtocol.decodeEvent(from: envelope)
                onEventReceived?(identity, event, wireSize)
            }
        } catch {
            onProtocolError?(error)
        }
    }

    private func closeIfNeeded() {
        guard !hasClosed else {
            return
        }

        hasClosed = true
        onConnectionClosed?(identity)
    }
}
#endif
