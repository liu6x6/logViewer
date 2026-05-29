#if os(macOS) && canImport(Pulse)
import Foundation
import Network
import Pulse

struct PulseRemoteLoggerPeerStateEvent: Identifiable, Sendable {
    enum State: Sendable {
        case connected
        case notConnected
    }

    let id: String
    let displayName: String
    let appName: String?
    let state: State
    let occurredAt: Date
}

enum PulseRemoteLoggerStoreEvent: Sendable {
    case message(LoggerStore.Event.MessageCreated)
    case networkTaskCreated(LoggerStore.Event.NetworkTaskCreated)
    case networkTaskProgressUpdated(LoggerStore.Event.NetworkTaskProgressUpdated)
    case networkTaskCompleted(LoggerStore.Event.NetworkTaskCompleted)
}

struct PulseRemoteLoggerReceivedEvent: Identifiable, Sendable {
    let id: String
    let peerID: String
    let displayName: String
    let appName: String?
    let storeEvent: PulseRemoteLoggerStoreEvent
    let byteCount: Int
    let receivedAt: Date

    var payloadPreview: String {
        switch storeEvent {
        case .message(let message):
            return message.message
        case .networkTaskCreated(let task):
            return "\(task.originalRequest.httpMethod ?? "REQUEST") \(task.originalRequest.url?.absoluteString ?? "Unknown URL")"
        case .networkTaskProgressUpdated(let progress):
            let progressText = progress.totalUnitCount > 0
                ? "\(progress.completedUnitCount)/\(progress.totalUnitCount)"
                : "\(progress.completedUnitCount)"
            return "\(progress.url?.absoluteString ?? "Unknown URL") · \(progressText)"
        case .networkTaskCompleted(let task):
            let method = task.originalRequest.httpMethod ?? "REQUEST"
            let url = task.originalRequest.url?.absoluteString ?? "Unknown URL"
            let status = task.response?.statusCode.map(String.init) ?? (task.error == nil ? "done" : "failed")
            return "\(method) \(url) · \(status)"
        }
    }
}

@MainActor
final class PulseRemoteLoggerServer {
    var onPeerStateChange: ((PulseRemoteLoggerPeerStateEvent) -> Void)?
    var onEventReceived: ((PulseRemoteLoggerReceivedEvent) -> Void)?

    private var listener: NWListener?
    private var activeConnections: [UUID: PulseRemoteLoggerClientConnection] = [:]
    private let listenerQueue = DispatchQueue(label: "logviewer.pulse.remote-listener")
    private let serviceName: String

    init(serviceName: String = PulseRemoteLoggerServer.makeDefaultServiceName()) {
        self.serviceName = serviceName
        start()
    }

    func stop() {
        listener?.stateUpdateHandler = nil
        listener?.newConnectionHandler = nil
        listener?.cancel()
        listener = nil

        activeConnections.values.forEach { $0.stop() }
        activeConnections.removeAll()
    }

    private func start() {
        do {
            let listener = try NWListener(using: .tcp)
            listener.service = NWListener.Service(name: serviceName, type: PulseRemoteLoggerProtocol.bonjourService)
            listener.stateUpdateHandler = { state in
                if case .failed(let error) = state {
                    print("[logViewer][PulseRemoteLogger] listener failed: \(error.localizedDescription)")
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
            print("[logViewer][PulseRemoteLogger] failed to start listener: \(error.localizedDescription)")
        }
    }

    private func registerConnection(_ connection: NWConnection) {
        let clientConnection = PulseRemoteLoggerClientConnection(connection: connection)

        clientConnection.onHandshake = { [weak self] identity in
            Task { @MainActor in
                self?.handleHandshake(identity, for: clientConnection)
            }
        }

        clientConnection.onStoreEvent = { [weak self] identity, storeEvent, byteCount in
            Task { @MainActor in
                self?.handleStoreEvent(storeEvent, from: identity, byteCount: byteCount)
            }
        }

        clientConnection.onConnectionClosed = { [weak self] identity in
            Task { @MainActor in
                self?.activeConnections[clientConnection.id] = nil
                self?.handleClosedConnection(clientID: identity?.stableIdentifier, displayName: identity?.displayName, appName: identity?.appName)
            }
        }

        clientConnection.onProtocolError = { error in
            print("[logViewer][PulseRemoteLogger] protocol error: \(error.localizedDescription)")
        }

        activeConnections[clientConnection.id] = clientConnection
        clientConnection.start()
    }

    private func handleHandshake(_ identity: PulseRemoteLoggerClientIdentity, for connection: PulseRemoteLoggerClientConnection) {
        activeConnections[connection.id] = connection

        onPeerStateChange?(
            PulseRemoteLoggerPeerStateEvent(
                id: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                state: .connected,
                occurredAt: .now
            )
        )
    }

    private func handleStoreEvent(
        _ storeEvent: PulseRemoteLoggerStoreEvent,
        from identity: PulseRemoteLoggerClientIdentity,
        byteCount: Int
    ) {
        onEventReceived?(
            PulseRemoteLoggerReceivedEvent(
                id: UUID().uuidString,
                peerID: identity.stableIdentifier,
                displayName: identity.displayName,
                appName: identity.appName,
                storeEvent: storeEvent,
                byteCount: byteCount,
                receivedAt: .now
            )
        )
    }

    private func handleClosedConnection(clientID: String?, displayName: String?, appName: String?) {
        guard let clientID, let displayName else {
            return
        }

        onPeerStateChange?(
            PulseRemoteLoggerPeerStateEvent(
                id: clientID,
                displayName: displayName,
                appName: appName,
                state: .notConnected,
                occurredAt: .now
            )
        )
    }

    nonisolated private static func makeDefaultServiceName() -> String {
        if let appName = Bundle.main.object(forInfoDictionaryKey: kCFBundleNameKey as String) as? String, !appName.isEmpty {
            return appName
        }
        return Host.current().localizedName ?? "logViewer"
    }
}

private struct PulseRemoteLoggerClientIdentity: Sendable {
    let deviceID: UUID
    let displayName: String
    let appName: String?
    let bundleIdentifier: String?

    var stableIdentifier: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "\(deviceID.uuidString)|\(bundleIdentifier)"
        }
        return deviceID.uuidString
    }

    init(_ hello: PulseRemoteLoggerClientHello) {
        self.deviceID = hello.deviceId
        self.displayName = hello.deviceInfo.name
        self.appName = hello.appInfo.name
        self.bundleIdentifier = hello.appInfo.bundleIdentifier
    }
}

private final class PulseRemoteLoggerClientConnection {
    let id = UUID()

    var onHandshake: ((PulseRemoteLoggerClientIdentity) -> Void)?
    var onStoreEvent: ((PulseRemoteLoggerClientIdentity, PulseRemoteLoggerStoreEvent, Int) -> Void)?
    var onConnectionClosed: ((PulseRemoteLoggerClientIdentity?) -> Void)?
    var onProtocolError: ((Error) -> Void)?

    private(set) var identity: PulseRemoteLoggerClientIdentity?

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "logviewer.pulse.remote-client")
    private var buffer = Data()
    private var pingTimer: DispatchSourceTimer?
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
        pingTimer?.cancel()
        pingTimer = nil
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
            guard let self else { return }

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
        var pendingData = incomingData

        if buffer.isEmpty {
            while let (packet, size) = decodePacket(from: pendingData) {
                handlePacket(packet, wireSize: size)
                if size == pendingData.count {
                    return
                }
                pendingData.removeFirst(size)
            }
        }

        if !pendingData.isEmpty {
            buffer.append(pendingData)
            while let (packet, size) = decodePacket(from: buffer) {
                handlePacket(packet, wireSize: size)
                buffer.removeFirst(size)
            }
            if buffer.isEmpty {
                buffer = Data()
            }
        }
    }

    private func decodePacket(from data: Data) -> (PulseRemoteLoggerWirePacket, Int)? {
        do {
            return try PulseRemoteLoggerProtocol.decodePacket(from: data)
        } catch PulseRemoteLoggerProtocolError.notEnoughData {
            return nil
        } catch {
            onProtocolError?(error)
            return nil
        }
    }

    private func handlePacket(_ packet: PulseRemoteLoggerWirePacket, wireSize: Int) {
        guard let code = PulseRemoteLoggerPacketCode(rawValue: packet.code) else {
            return
        }

        do {
            switch code {
            case .clientHello:
                let hello = try JSONDecoder().decode(PulseRemoteLoggerClientHello.self, from: packet.body)
                let identity = PulseRemoteLoggerClientIdentity(hello)
                self.identity = identity
                onHandshake?(identity)
                completeHandshake()
            case .storeEventMessageStored:
                guard let identity else { return }
                let event = try JSONDecoder().decode(LoggerStore.Event.MessageCreated.self, from: packet.body)
                onStoreEvent?(identity, .message(event), wireSize)
            case .storeEventNetworkTaskCreated:
                guard let identity else { return }
                let event = try JSONDecoder().decode(LoggerStore.Event.NetworkTaskCreated.self, from: packet.body)
                onStoreEvent?(identity, .networkTaskCreated(event), wireSize)
            case .storeEventNetworkTaskProgressUpdated:
                guard let identity else { return }
                let event = try JSONDecoder().decode(LoggerStore.Event.NetworkTaskProgressUpdated.self, from: packet.body)
                onStoreEvent?(identity, .networkTaskProgressUpdated(event), wireSize)
            case .storeEventNetworkTaskCompleted:
                guard let identity else { return }
                let event = try PulseRemoteLoggerProtocol.decodeNetworkCompleted(from: packet.body)
                onStoreEvent?(identity, .networkTaskCompleted(event), wireSize)
            case .message:
                try handleMessagePacket(packet.body)
            case .ping, .pause, .resume, .serverHello:
                break
            }
        } catch {
            onProtocolError?(error)
        }
    }

    private func handleMessagePacket(_ data: Data) throws {
        let message = try PulseRemoteLoggerMessage.decode(data)

        guard !message.options.contains(.response) else {
            return
        }

        switch message.path {
        case .getMockedResponse:
            sendResponse(for: message, data: Data())
        case .updateMocks, .openMessageDetails, .openTaskDetails:
            break
        }
    }

    private func completeHandshake() {
        send(code: .serverHello, entity: PulseRemoteLoggerServerHello(version: PulseRemoteLoggerProtocol.serverVersion))
        send(code: .resume, entity: PulseRemoteLoggerEmpty())
        startPingLoop()
    }

    private func startPingLoop() {
        pingTimer?.cancel()

        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + .seconds(2), repeating: .seconds(2))
        timer.setEventHandler { [weak self] in
            self?.send(code: .ping, entity: PulseRemoteLoggerEmpty())
        }
        timer.resume()
        pingTimer = timer
    }

    private func send<T: Encodable>(code: PulseRemoteLoggerPacketCode, entity: T) {
        do {
            let encodedBody = try JSONEncoder().encode(entity)
            try send(code: code.rawValue, body: encodedBody)
        } catch {
            onProtocolError?(error)
        }
    }

    private func sendResponse(for message: PulseRemoteLoggerMessage, data: Data) {
        do {
            let response = PulseRemoteLoggerMessage(
                id: message.id,
                options: [.response],
                path: message.path,
                data: data
            )
            let encodedMessage = try PulseRemoteLoggerMessage.encode(response)
            try send(code: PulseRemoteLoggerPacketCode.message.rawValue, body: encodedMessage)
        } catch {
            onProtocolError?(error)
        }
    }

    private func send(code: UInt8, body: Data) throws {
        let packet = try PulseRemoteLoggerProtocol.encodePacket(code: code, body: body)
        connection.send(content: packet, completion: .contentProcessed { [weak self] error in
            if let error {
                self?.onProtocolError?(error)
            }
        })
    }

    private func closeIfNeeded() {
        guard !hasClosed else {
            return
        }
        hasClosed = true

        pingTimer?.cancel()
        pingTimer = nil
        onConnectionClosed?(identity)
    }
}
#endif
