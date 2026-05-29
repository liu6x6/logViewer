#if os(macOS) && canImport(Pulse)
import Foundation
import Pulse

@MainActor
final class PulseStoreInjector {
    enum StoreLocation: String, Sendable {
        case inMemory = "In-Memory"
        case temporarySandbox = "Temporary Sandbox"
    }

    let store: LoggerStore
    let storeLocation: StoreLocation
    let storeURL: URL

    private let decoder = LogPacketDecoder()

    init(storeLocation: StoreLocation = .temporarySandbox) {
        self.storeLocation = storeLocation
        self.storeURL = Self.makeStoreURL(for: storeLocation)

        let options = Self.makeOptions(for: storeLocation)

        do {
            self.store = try LoggerStore(storeURL: storeURL, options: options)
        } catch {
            fatalError("Failed to initialize Pulse LoggerStore: \(error.localizedDescription)")
        }
    }

    func injectReceivedPacket(_ packet: LogViewerReceivedPacket) {
        do {
            let decodedPacket = try decoder.decodeEnvelopeAndPayload(from: packet.data)
            inject(decodedPacket, peerDisplayName: packet.displayName)
        } catch {
            injectTransportFailure(
                message: "Failed to decode packet from \(packet.displayName): \(error.localizedDescription)",
                timestamp: packet.receivedAt
            )
        }
    }

    func inject(_ decodedPacket: DecodedLogPacket, peerDisplayName: String) {
        switch decodedPacket {
        case .message(let packet, let payload):
            injectLogMessage(payload, envelope: packet, peerDisplayName: peerDisplayName)
        case .network(let packet, let payload):
            injectNetworkSummary(payload, envelope: packet, peerDisplayName: peerDisplayName)
        }
    }

    func injectLogMessage(
        _ payload: LogMessagePayload,
        envelope: LogPacket,
        peerDisplayName: String
    ) {
        store.storeMessage(
            createdAt: Date(timeIntervalSince1970: envelope.timestamp),
            label: makeMessageLabel(category: payload.category, peerDisplayName: peerDisplayName),
            level: mapLevel(payload.level),
            message: payload.message,
            metadata: nil,
            file: "RemoteLogPacket",
            function: "MultipeerConnectivity",
            line: 0
        )
    }

    func injectNetworkSummary(
        _ payload: LogNetworkPayload,
        envelope: LogPacket,
        peerDisplayName: String
    ) {
        guard let url = URL(string: payload.url) else {
            injectTransportFailure(
                message: "Dropped network packet with invalid URL: \(payload.url)",
                timestamp: Date(timeIntervalSince1970: envelope.timestamp)
            )
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = payload.method
        request.allHTTPHeaderFields = payload.requestHeaders.isEmpty ? nil : payload.requestHeaders
        request.timeoutInterval = 60

        let response = HTTPURLResponse(
            url: url,
            statusCode: sanitizeStatusCode(payload.statusCode),
            httpVersion: "HTTP/1.1",
            headerFields: payload.responseHeaders.isEmpty ? nil : payload.responseHeaders
        )

        // `storeRequest` is the supported public Pulse API. It persists headers,
        // status code, and body blobs so PulseUI can render the response body
        // using the Content-Type from the supplied response headers.
        store.storeRequest(
            request,
            response: response,
            error: nil,
            data: payload.responseBody,
            metrics: nil,
            label: peerDisplayName,
            taskDescription: makeTaskDescription(remoteTimestamp: envelope.timestamp)
        )
    }

    var storeDescription: String {
        "\(storeLocation.rawValue) · \(storeURL.lastPathComponent)"
    }

    private func injectTransportFailure(message: String, timestamp: Date) {
        store.storeMessage(
            createdAt: timestamp,
            label: "transport",
            level: .error,
            message: message,
            metadata: nil,
            file: "PulseStoreInjector",
            function: #function,
            line: 0
        )
    }

    private func makeMessageLabel(category: String, peerDisplayName: String) -> String {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCategory.isEmpty {
            return peerDisplayName
        }
        return "\(peerDisplayName) · \(trimmedCategory)"
    }

    private func makeTaskDescription(remoteTimestamp: TimeInterval) -> String {
        let date = Date(timeIntervalSince1970: remoteTimestamp)
        return "Remote packet @ \(date.formatted(.dateTime.year().month().day().hour().minute().second()))"
    }

    private func mapLevel(_ level: LogMessageLevel) -> LoggerStore.Level {
        switch level {
        case .debug:
            return .debug
        case .info:
            return .info
        case .error:
            return .error
        }
    }

    private func sanitizeStatusCode(_ statusCode: Int) -> Int {
        guard (100 ... 999).contains(statusCode) else {
            return 200
        }
        return statusCode
    }

    private static func makeStoreURL(for location: StoreLocation) -> URL {
        switch location {
        case .inMemory:
            return URL(fileURLWithPath: "/dev/null/\(UUID().uuidString)")
        case .temporarySandbox:
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("logviewer-live-\(UUID().uuidString).pulse", isDirectory: true)
        }
    }

    private static func makeOptions(for location: StoreLocation) -> LoggerStore.Options {
        switch location {
        case .inMemory:
            return [.create, .inMemory, .synchronous]
        case .temporarySandbox:
            return [.create, .synchronous]
        }
    }
}
#elseif os(macOS)
import Foundation

@MainActor
final class PulseStoreInjector {
    enum StoreLocation: String, Sendable {
        case inMemory = "In-Memory"
        case temporarySandbox = "Temporary Sandbox"
    }

    let storeLocation: StoreLocation
    let storeURL: URL

    init(storeLocation: StoreLocation = .temporarySandbox) {
        self.storeLocation = storeLocation
        self.storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("logviewer-live-placeholder.pulse", isDirectory: true)
    }

    func injectReceivedPacket(_ packet: LogViewerReceivedPacket) {}

    var storeDescription: String {
        "Pulse not linked"
    }
}
#endif
