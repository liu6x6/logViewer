import Combine
import Foundation

@MainActor
final class ConnectionManager: ObservableObject {
    @Published private(set) var devices: [DeviceModel] = []
    @Published private(set) var connectedDeviceNames: [String] = []
    @Published private(set) var latestReceivedPayload: String?
    let networkBlocklist: NetworkRequestBlocklist

    #if os(macOS)
    private let receiver: MacLogReceiver
    private let remoteLoggerServer: PulseRemoteLoggerServer
    let pulseInjector: PulseStoreInjector
    #endif

    private var lastPacketDateByDeviceID: [DeviceModel.ID: Date] = [:]

    #if os(macOS)
    init(
        receiver: MacLogReceiver? = nil,
        remoteLoggerServer: PulseRemoteLoggerServer? = nil,
        networkBlocklist: NetworkRequestBlocklist? = nil,
        pulseInjector: PulseStoreInjector? = nil
    ) {
        let resolvedBlocklist = networkBlocklist ?? NetworkRequestBlocklist()
        self.networkBlocklist = resolvedBlocklist
        self.receiver = receiver ?? MacLogReceiver()
        self.remoteLoggerServer = remoteLoggerServer ?? PulseRemoteLoggerServer()
        self.pulseInjector = pulseInjector ?? PulseStoreInjector(blocklist: resolvedBlocklist)
        bindReceiver()
        bindRemoteLoggerServer()
    }
    #else
    init(networkBlocklist: NetworkRequestBlocklist = NetworkRequestBlocklist()) {
        self.networkBlocklist = networkBlocklist
    }
    #endif
}

#if os(macOS)
extension ConnectionManager {
    func bindReceiver() {
        receiver.onPeerStateChange = { [weak self] event in
            self?.handlePeerStateChange(event)
        }

        receiver.onPacketReceived = { [weak self] packet in
            self?.handleReceivedPacket(packet)
        }
    }

    func bindRemoteLoggerServer() {
        remoteLoggerServer.onPeerStateChange = { [weak self] event in
            self?.handleRemoteLoggerPeerStateChange(event)
        }

        remoteLoggerServer.onEventReceived = { [weak self] event in
            self?.handleRemoteLoggerEvent(event)
        }
    }

    func handlePeerStateChange(_ event: LogViewerPeerStateEvent) {
        let index = ensureDevice(id: event.id, displayName: event.displayName)
        let wasConnected = devices[index].status == .connected

        switch event.state {
        case .connecting:
            break
        case .connected:
            devices[index].status = .connected
            if !wasConnected {
                devices[index].appendHistory(note: "Auto-connected over local Wi-Fi", timestamp: event.occurredAt)
            }
        case .notConnected:
            devices[index].status = .disconnected
            devices[index].transferRateKBps = 0
            lastPacketDateByDeviceID.removeValue(forKey: event.id)

            if wasConnected {
                devices[index].appendHistory(note: "Disconnected", timestamp: event.occurredAt)
            }
        }

        refreshConnectedDeviceNames()
        sortDevices()
    }

    func handleReceivedPacket(_ packet: LogViewerReceivedPacket) {
        let index = ensureDevice(id: packet.peerID, displayName: packet.displayName)
        let previousPacketDate = lastPacketDateByDeviceID[packet.peerID]

        devices[index].status = .connected
        devices[index].transferRateKBps = transferRate(for: packet.data.count, previousPacketDate: previousPacketDate, currentDate: packet.receivedAt)

        lastPacketDateByDeviceID[packet.peerID] = packet.receivedAt
        latestReceivedPayload = packet.payloadPreview
        pulseInjector.injectReceivedPacket(packet)

        refreshConnectedDeviceNames()
        sortDevices()
    }

    func handleRemoteLoggerPeerStateChange(_ event: PulseRemoteLoggerPeerStateEvent) {
        let index = ensureDevice(id: event.id, displayName: event.displayName)
        let wasConnected = devices[index].status == .connected
        let connectionLabel = event.appName.map { "Pulse RemoteLogger · \($0)" } ?? "Pulse RemoteLogger"

        switch event.state {
        case .connected:
            devices[index].status = .connected
            if !wasConnected {
                devices[index].appendHistory(note: "Connected via \(connectionLabel)", timestamp: event.occurredAt)
            }
        case .notConnected:
            devices[index].status = .disconnected
            devices[index].transferRateKBps = 0
            lastPacketDateByDeviceID.removeValue(forKey: event.id)

            if wasConnected {
                devices[index].appendHistory(note: "\(connectionLabel) disconnected", timestamp: event.occurredAt)
            }
        }

        refreshConnectedDeviceNames()
        sortDevices()
    }

    func handleRemoteLoggerEvent(_ event: PulseRemoteLoggerReceivedEvent) {
        let index = ensureDevice(id: event.peerID, displayName: event.displayName)
        let previousPacketDate = lastPacketDateByDeviceID[event.peerID]

        devices[index].status = .connected
        devices[index].transferRateKBps = transferRate(
            for: event.byteCount,
            previousPacketDate: previousPacketDate,
            currentDate: event.receivedAt
        )

        lastPacketDateByDeviceID[event.peerID] = event.receivedAt
        latestReceivedPayload = event.payloadPreview
        pulseInjector.injectRemoteLoggerEvent(event.storeEvent, peerDisplayName: event.displayName)

        refreshConnectedDeviceNames()
        sortDevices()
    }

    func ensureDevice(id: DeviceModel.ID, displayName: String) -> Int {
        if let existingIndex = devices.firstIndex(where: { $0.id == id }) {
            devices[existingIndex].name = displayName
            return existingIndex
        }

        let newDevice = DeviceModel(id: id, name: displayName)
        devices.insert(newDevice, at: 0)
        return 0
    }

    func transferRate(for byteCount: Int, previousPacketDate: Date?, currentDate: Date) -> Double {
        guard let previousPacketDate else {
            return max(Double(byteCount) / 1024, 1)
        }

        let interval = max(currentDate.timeIntervalSince(previousPacketDate), 0.05)
        return max((Double(byteCount) / 1024) / interval, 1)
    }

    func refreshConnectedDeviceNames() {
        connectedDeviceNames = devices
            .filter { $0.status == .connected }
            .map(\.name)
            .sorted()
    }

    func sortDevices() {
        devices.sort { lhs, rhs in
            if lhs.status != rhs.status {
                return lhs.status == .connected
            }

            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func clearStoredRecords() {
        latestReceivedPayload = nil
        lastPacketDateByDeviceID.removeAll()
        pulseInjector.clearAllRecords()

        for index in devices.indices {
            devices[index].transferRateKBps = 0
            devices[index].connectionHistory.removeAll()
        }

        refreshConnectedDeviceNames()
        sortDevices()
    }
}
#endif
