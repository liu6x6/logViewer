import LogViewerCustomMode

#if os(macOS) && canImport(Pulse)
import CoreData
import Foundation
import Pulse

@MainActor
final class PulseStoreInjector {
    enum StoreLocation: String, Sendable {
        case inMemory = "In-Memory"
        case temporarySandbox = "Temporary Sandbox"
    }

    let store: LoggerStore
    let blocklist: NetworkRequestBlocklist
    let storeLocation: StoreLocation
    let storeURL: URL

    private let decoder = LogPacketDecoder()

    init(
        storeLocation: StoreLocation = .temporarySandbox,
        blocklist: NetworkRequestBlocklist? = nil
    ) {
        self.blocklist = blocklist ?? NetworkRequestBlocklist()
        self.storeLocation = storeLocation
        self.storeURL = Self.makeStoreURL(for: storeLocation)

        let options = Self.makeOptions(for: storeLocation)

        do {
            self.store = try LoggerStore(storeURL: storeURL, options: options)
            self.store.viewContext.automaticallyMergesChangesFromParent = true
        } catch {
            fatalError("Failed to initialize Pulse LoggerStore: \(error.localizedDescription)")
        }
    }

    func injectReceivedPacket(_ packet: LogViewerReceivedPacket) {
        do {
            let decodedPacket = try decoder.decodeEnvelopeAndPayload(from: packet.data)
            inject(decodedPacket, peerID: packet.peerID, peerDisplayName: packet.displayName)
        } catch {
            injectTransportFailure(
                message: "Failed to decode packet from \(packet.displayName): \(error.localizedDescription)",
                timestamp: packet.receivedAt
            )
        }
    }

    func inject(_ decodedPacket: DecodedLogPacket, peerID: String, peerDisplayName: String) {
        switch decodedPacket {
        case .message(let packet, let payload):
            injectLogMessage(payload, envelope: packet, peerDisplayName: peerDisplayName)
        case .network(let packet, let payload):
            injectNetworkSummary(payload, envelope: packet, peerID: peerID, peerDisplayName: peerDisplayName)
        }
    }

    func injectRemoteLoggerEvent(_ event: PulseRemoteLoggerStoreEvent, peerID: String, peerDisplayName: String) {
        switch event {
        case .message(let message):
            injectRemoteLoggerMessage(message, peerDisplayName: peerDisplayName)
        case .networkTaskCreated, .networkTaskProgressUpdated:
            break
        case .networkTaskCompleted(let task):
            injectRemoteLoggerNetworkTask(task, peerID: peerID, peerDisplayName: peerDisplayName)
        }
    }

    func injectAndroidRemoteLoggerEvent(
        _ event: AndroidRemoteLoggerReceivedEvent,
        peerDisplayName: String
    ) {
        switch event.event {
        case .message(let payload):
            injectAndroidRemoteLoggerMessage(
                payload,
                peerDisplayName: peerDisplayName,
                appName: event.appName
            )
        case .networkCompleted(let payload):
            injectAndroidRemoteLoggerNetworkTask(
                payload,
                peerID: event.peerID,
                peerDisplayName: peerDisplayName,
                appName: event.appName
            )
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
        peerID: String,
        peerDisplayName: String
    ) {
        guard let url = URL(string: payload.url) else {
            injectTransportFailure(
                message: "Dropped network packet with invalid URL: \(payload.url)",
                timestamp: Date(timeIntervalSince1970: envelope.timestamp)
            )
            return
        }

        guard !blocklist.snapshot.matches(url: url) else {
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
            taskDescription: makeTaskDescription(remoteTimestamp: envelope.timestamp, peerID: peerID)
        )
    }

    func injectRemoteLoggerMessage(
        _ event: LoggerStore.Event.MessageCreated,
        peerDisplayName: String
    ) {
        store.storeMessage(
            createdAt: event.createdAt,
            label: makeMessageLabel(category: event.label, peerDisplayName: peerDisplayName),
            level: event.level,
            message: event.message,
            metadata: makeMetadataValues(from: event.metadata),
            file: event.file,
            function: event.function,
            line: event.line
        )
    }

    func injectRemoteLoggerNetworkTask(
        _ event: LoggerStore.Event.NetworkTaskCompleted,
        peerID: String,
        peerDisplayName: String
    ) {
        guard let url = event.originalRequest.url else {
            injectTransportFailure(
                message: "Dropped Pulse RemoteLogger task with missing URL from \(peerDisplayName)",
                timestamp: event.createdAt
            )
            return
        }

        guard !blocklist.snapshot.matches(url: url) else {
            return
        }

        var request = URLRequest(
            url: url,
            cachePolicy: event.originalRequest.cachePolicy,
            timeoutInterval: max(event.originalRequest.timeout, 0.1)
        )
        request.httpMethod = event.originalRequest.httpMethod
        request.allHTTPHeaderFields = event.originalRequest.headers
        request.httpBody = event.requestBody
        request.allowsCellularAccess = event.originalRequest.options.contains(.allowsCellularAccess)
        request.allowsExpensiveNetworkAccess = event.originalRequest.options.contains(.allowsExpensiveNetworkAccess)
        request.allowsConstrainedNetworkAccess = event.originalRequest.options.contains(.allowsConstrainedNetworkAccess)
        request.httpShouldHandleCookies = event.originalRequest.options.contains(.httpShouldHandleCookies)

        let response = makeHTTPResponse(for: event.response, requestURL: url)
        let error = event.error.map(makeRemoteResponseError)

        store.storeRequest(
            request,
            response: response,
            error: error,
            data: event.responseBody,
            metrics: nil,
            label: makeMessageLabel(category: event.label ?? "network", peerDisplayName: peerDisplayName),
            taskDescription: makeRemoteTaskDescription(for: event, peerID: peerID)
        )
    }

    func injectAndroidRemoteLoggerMessage(
        _ payload: AndroidRemoteLoggerMessagePayload,
        peerDisplayName: String,
        appName: String
    ) {
        store.storeMessage(
            createdAt: Date(millisecondsSince1970: payload.timestamp),
            label: makeAndroidMessageLabel(
                category: payload.category,
                peerDisplayName: peerDisplayName,
                appName: appName
            ),
            level: mapAndroidLevel(payload.level),
            message: payload.message,
            metadata: makeAndroidMetadataValues(from: payload),
            file: payload.tag ?? "AndroidRemoteLogger",
            function: payload.thread ?? "Android",
            line: 0
        )
    }

    func injectAndroidRemoteLoggerNetworkTask(
        _ payload: AndroidRemoteLoggerNetworkCompletedPayload,
        peerID: String,
        peerDisplayName: String,
        appName: String
    ) {
        guard let url = URL(string: payload.url) else {
            injectTransportFailure(
                message: "Dropped Android network task with invalid URL: \(payload.url)",
                timestamp: Date(millisecondsSince1970: payload.timestamp)
            )
            return
        }

        guard !blocklist.snapshot.matches(url: url) else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = payload.method
        request.allHTTPHeaderFields = payload.requestHeaders.isEmpty ? nil : payload.requestHeaders
        request.httpBody = payload.requestBody?.data(using: .utf8)
        request.timeoutInterval = max(Double(payload.durationMs) / 1000, 0.1)

        let response = payload.statusCode.flatMap {
            HTTPURLResponse(
                url: url,
                statusCode: sanitizeStatusCode($0),
                httpVersion: "HTTP/1.1",
                headerFields: payload.responseHeaders.isEmpty ? nil : payload.responseHeaders
            )
        } ?? nil

        let error = payload.error.map {
            NSError(
                domain: "AndroidRemoteLogger",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: $0]
            )
        }

        let responseData = payload.responseBody?.data(using: .utf8)

        store.storeRequest(
            request,
            response: response,
            error: error,
            data: responseData,
            metrics: nil,
            label: makeAndroidMessageLabel(
                category: "network",
                peerDisplayName: peerDisplayName,
                appName: appName
            ),
            taskDescription: makeAndroidTaskDescription(for: payload, peerID: peerID)
        )
    }

    var storeDescription: String {
        "\(storeLocation.rawValue) · \(storeURL.lastPathComponent)"
    }

    func clearAllRecords() {
        store.removeAll()
    }

    func messageEntity(for objectID: NSManagedObjectID) -> LoggerMessageEntity? {
        try? store.viewContext.existingObject(with: objectID) as? LoggerMessageEntity
    }

    func networkTaskEntity(for objectID: NSManagedObjectID) -> NetworkTaskEntity? {
        try? store.viewContext.existingObject(with: objectID) as? NetworkTaskEntity
    }

    static func messagePredicate(for device: DeviceModel?) -> NSPredicate? {
        guard let device else {
            return nil
        }

        return Self.messagePredicate(forDeviceName: device.name)
    }

    static func networkPredicate(for device: DeviceModel?) -> NSPredicate? {
        guard let device else {
            return nil
        }

        return NSPredicate(format: "taskDescription CONTAINS %@", Self.networkTaskMarker(for: device.id))
    }

    func sendAgain(for task: NetworkTaskEntity) async throws {
        let request = try task.makeReplayRequest()

        guard let requestURL = request.url else {
            throw NetworkRequestReplayError.invalidURL(task.url)
        }

        guard !blocklist.snapshot.matches(url: requestURL) else {
            throw NetworkRequestReplayError.blockedURL(requestURL.absoluteString)
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            store.storeRequest(
                request,
                response: response as? HTTPURLResponse,
                error: nil,
                data: data,
                metrics: nil,
                label: "Inspector Replay",
                taskDescription: task.replayTaskDescription
            )
        } catch {
            store.storeRequest(
                request,
                response: nil,
                error: error as NSError,
                data: nil,
                metrics: nil,
                label: "Inspector Replay",
                taskDescription: task.replayTaskDescription
            )
            throw error
        }
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

    private static func messagePredicate(forDeviceName deviceName: String) -> NSPredicate {
        NSPredicate(
            format: "label == %@ OR label BEGINSWITH %@",
            deviceName,
            "\(deviceName) ·"
        )
    }

    private static func networkTaskMarker(for peerID: String) -> String {
        "[logviewer-device:\(peerID)]"
    }

    private func makeMessageLabel(category: String, peerDisplayName: String) -> String {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCategory.isEmpty {
            return peerDisplayName
        }
        return "\(peerDisplayName) · \(trimmedCategory)"
    }

    private func makeAndroidMessageLabel(category: String, peerDisplayName: String, appName: String) -> String {
        let trimmedCategory = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = "\(peerDisplayName) · \(appName)"
        if trimmedCategory.isEmpty {
            return base
        }
        return "\(base) · \(trimmedCategory)"
    }

    private func makeTaskDescription(remoteTimestamp: TimeInterval, peerID: String) -> String {
        let date = Date(timeIntervalSince1970: remoteTimestamp)
        return decorateNetworkTaskDescription(
            "Remote packet @ \(date.formatted(.dateTime.year().month().day().hour().minute().second()))",
            peerID: peerID
        )
    }

    private func makeRemoteTaskDescription(for event: LoggerStore.Event.NetworkTaskCompleted, peerID: String) -> String {
        let timestamp = event.createdAt.formatted(.dateTime.year().month().day().hour().minute().second())
        if let originalDescription = event.taskDescription, !originalDescription.isEmpty {
            return decorateNetworkTaskDescription(
                "\(originalDescription) · RemoteLogger @ \(timestamp)",
                peerID: peerID
            )
        }
        return decorateNetworkTaskDescription("Pulse RemoteLogger @ \(timestamp)", peerID: peerID)
    }

    private func makeAndroidTaskDescription(for payload: AndroidRemoteLoggerNetworkCompletedPayload, peerID: String) -> String {
        let timestamp = Date(millisecondsSince1970: payload.timestamp)
            .formatted(.dateTime.year().month().day().hour().minute().second())
        return decorateNetworkTaskDescription(
            "Android RemoteLogger @ \(timestamp) · \(payload.durationMs) ms",
            peerID: peerID
        )
    }

    private func decorateNetworkTaskDescription(_ description: String, peerID: String) -> String {
        "\(Self.networkTaskMarker(for: peerID)) \(description)"
    }

    private func makeMetadataValues(from metadata: [String: String]?) -> [String: LoggerStore.MetadataValue]? {
        guard let metadata, !metadata.isEmpty else {
            return nil
        }
        return metadata.mapValues(LoggerStore.MetadataValue.string)
    }

    private func makeAndroidMetadataValues(
        from payload: AndroidRemoteLoggerMessagePayload
    ) -> [String: LoggerStore.MetadataValue]? {
        var metadata: [String: String] = [:]

        if let tag = payload.tag, !tag.isEmpty {
            metadata["tag"] = tag
        }
        if let thread = payload.thread, !thread.isEmpty {
            metadata["thread"] = thread
        }

        return makeMetadataValues(from: metadata.isEmpty ? nil : metadata)
    }

    private func makeHTTPResponse(
        for response: NetworkLogger.Response?,
        requestURL: URL
    ) -> HTTPURLResponse? {
        guard let response else {
            return nil
        }

        return HTTPURLResponse(
            url: requestURL,
            statusCode: sanitizeStatusCode(response.statusCode ?? 200),
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )
    }

    private func makeRemoteResponseError(_ error: NetworkLogger.ResponseError) -> NSError {
        if let underlyingError = error.error as NSError? {
            return underlyingError
        }

        return NSError(
            domain: error.domain,
            code: error.code,
            userInfo: [
                NSLocalizedDescriptionKey: error.debugDescription,
                NSDebugDescriptionErrorKey: error.debugDescription
            ]
        )
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

    private func mapAndroidLevel(_ level: AndroidRemoteLoggerLogLevel) -> LoggerStore.Level {
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

private extension Date {
    init(millisecondsSince1970: Int64) {
        self = Date(timeIntervalSince1970: TimeInterval(millisecondsSince1970) / 1000)
    }
}
#elseif os(macOS)
import Foundation

@MainActor
final class PulseStoreInjector {
    let blocklist: NetworkRequestBlocklist
    enum StoreLocation: String, Sendable {
        case inMemory = "In-Memory"
        case temporarySandbox = "Temporary Sandbox"
    }

    let storeLocation: StoreLocation
    let storeURL: URL

    init(
        storeLocation: StoreLocation = .temporarySandbox,
        blocklist: NetworkRequestBlocklist? = nil
    ) {
        self.blocklist = blocklist ?? NetworkRequestBlocklist()
        self.storeLocation = storeLocation
        self.storeURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("logviewer-live-placeholder.pulse", isDirectory: true)
    }

    func injectReceivedPacket(_ packet: LogViewerReceivedPacket) {}

    func injectRemoteLoggerEvent(_ event: Any, peerDisplayName: String) {}

    func injectAndroidRemoteLoggerEvent(_ event: Any, peerDisplayName: String) {}

    var storeDescription: String {
        "Pulse not linked"
    }

    func clearAllRecords() {}

    func messageEntity(for objectID: Any) -> Any? { nil }

    func networkTaskEntity(for objectID: Any) -> Any? { nil }
}
#endif
