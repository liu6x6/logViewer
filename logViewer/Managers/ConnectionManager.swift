import Combine
import Foundation
import LogViewerCustomMode

@MainActor
final class ConnectionManager: ObservableObject {
    @Published private(set) var devices: [DeviceModel] = []
    @Published private(set) var connectedDeviceNames: [String] = []
    @Published private(set) var latestReceivedPayload: String?
    let networkBlocklist: NetworkRequestBlocklist

    #if os(macOS)
    private let receiver: MacLogReceiver
    private let remoteLoggerServer: PulseRemoteLoggerServer
    private let androidRemoteLoggerServer: AndroidRemoteLoggerServer
    private let androidRemoteLoggerBrowser: AndroidRemoteLoggerBrowser
    let pulseInjector: PulseStoreInjector
    #endif

    private var lastPacketDateByDeviceID: [DeviceModel.ID: Date] = [:]

    #if os(macOS)
    init(
        receiver: MacLogReceiver? = nil,
        remoteLoggerServer: PulseRemoteLoggerServer? = nil,
        androidRemoteLoggerServer: AndroidRemoteLoggerServer? = nil,
        androidRemoteLoggerBrowser: AndroidRemoteLoggerBrowser? = nil,
        networkBlocklist: NetworkRequestBlocklist? = nil,
        pulseInjector: PulseStoreInjector? = nil
    ) {
        let resolvedBlocklist = networkBlocklist ?? NetworkRequestBlocklist()
        self.networkBlocklist = resolvedBlocklist
        self.receiver = receiver ?? MacLogReceiver()
        self.remoteLoggerServer = remoteLoggerServer ?? PulseRemoteLoggerServer()
        self.androidRemoteLoggerServer = androidRemoteLoggerServer ?? AndroidRemoteLoggerServer()
        self.androidRemoteLoggerBrowser = androidRemoteLoggerBrowser ?? AndroidRemoteLoggerBrowser()
        self.pulseInjector = pulseInjector ?? PulseStoreInjector(blocklist: resolvedBlocklist)
        bindReceiver()
        bindRemoteLoggerServer()
        bindAndroidRemoteLoggerServer()
        bindAndroidRemoteLoggerBrowser()
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

    func bindAndroidRemoteLoggerServer() {
        androidRemoteLoggerServer.onPeerStateChange = { [weak self] event in
            self?.handleAndroidRemoteLoggerPeerStateChange(event)
        }

        androidRemoteLoggerServer.onEventReceived = { [weak self] event in
            self?.handleAndroidRemoteLoggerEvent(event)
        }
    }

    func bindAndroidRemoteLoggerBrowser() {
        androidRemoteLoggerBrowser.onPeerStateChange = { [weak self] event in
            self?.handleAndroidRemoteLoggerPeerStateChange(event)
        }

        androidRemoteLoggerBrowser.onEventReceived = { [weak self] event in
            self?.handleAndroidRemoteLoggerEvent(event)
        }
    }

    func handlePeerStateChange(_ event: LogViewerPeerStateEvent) {
        let index = ensureDevice(id: event.id, displayName: event.displayName, platform: .ios)
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
        let index = ensureDevice(id: packet.peerID, displayName: packet.displayName, platform: .ios)
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
        let index = ensureDevice(id: event.id, displayName: event.displayName, platform: .ios)
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
        let index = ensureDevice(id: event.peerID, displayName: event.displayName, platform: .ios)
        let previousPacketDate = lastPacketDateByDeviceID[event.peerID]

        devices[index].status = .connected
        devices[index].transferRateKBps = transferRate(
            for: event.byteCount,
            previousPacketDate: previousPacketDate,
            currentDate: event.receivedAt
        )

        lastPacketDateByDeviceID[event.peerID] = event.receivedAt
        latestReceivedPayload = event.payloadPreview
        pulseInjector.injectRemoteLoggerEvent(
            event.storeEvent,
            peerID: event.peerID,
            peerDisplayName: event.displayName
        )

        refreshConnectedDeviceNames()
        sortDevices()
    }

    func handleAndroidRemoteLoggerPeerStateChange(_ event: AndroidRemoteLoggerPeerStateEvent) {
        let index = ensureDevice(id: event.id, displayName: event.displayName, platform: .android)
        let wasConnected = devices[index].status == .connected
        let connectionLabel = "Android SDK · \(event.appName)"

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

    func handleAndroidRemoteLoggerEvent(_ event: AndroidRemoteLoggerReceivedEvent) {
        let index = ensureDevice(id: event.peerID, displayName: event.displayName, platform: .android)
        let previousPacketDate = lastPacketDateByDeviceID[event.peerID]

        devices[index].status = .connected
        devices[index].transferRateKBps = transferRate(
            for: event.byteCount,
            previousPacketDate: previousPacketDate,
            currentDate: event.receivedAt
        )

        lastPacketDateByDeviceID[event.peerID] = event.receivedAt
        latestReceivedPayload = event.payloadPreview
        pulseInjector.injectAndroidRemoteLoggerEvent(event, peerDisplayName: event.displayName)

        refreshConnectedDeviceNames()
        sortDevices()
    }

    func ensureDevice(id: DeviceModel.ID, displayName: String, platform: DevicePlatform) -> Int {
        if let existingIndex = devices.firstIndex(where: { $0.id == id }) {
            devices[existingIndex].name = displayName
            devices[existingIndex].platform = platform
            return existingIndex
        }

        let newDevice = DeviceModel(id: id, name: displayName, platform: platform)
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
