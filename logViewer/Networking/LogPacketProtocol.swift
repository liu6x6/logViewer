import Foundation

nonisolated enum LogPacketType: Int, Codable, CaseIterable, Sendable {
    case message = 1
    case networkSummary = 2
}

nonisolated enum LogMessageLevel: Int, Codable, CaseIterable, Sendable {
    case debug = 0
    case info = 1
    case error = 2

    nonisolated var title: String {
        switch self {
        case .debug:
            return "Debug"
        case .info:
            return "Info"
        case .error:
            return "Error"
        }
    }
}

/// Shared envelope transported over MultipeerConnectivity.
/// The payload is encoded separately to keep the framing stable across packet kinds.
nonisolated struct LogPacket: Codable, Hashable, Sendable {
    static let currentVersion = "1.0"

    let version: String
    let timestamp: TimeInterval
    let packetType: Int
    let payload: Data

    init(
        version: String = LogPacket.currentVersion,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        packetType: LogPacketType,
        payload: Data
    ) {
        self.version = version
        self.timestamp = timestamp
        self.packetType = packetType.rawValue
        self.payload = payload
    }

    var type: LogPacketType? {
        LogPacketType(rawValue: packetType)
    }

    enum CodingKeys: String, CodingKey {
        case version = "v"
        case timestamp = "ts"
        case packetType = "pt"
        case payload = "pl"
    }
}

nonisolated struct LogMessagePayload: Codable, Hashable, Sendable {
    let message: String
    let level: LogMessageLevel
    let category: String

    init(message: String, level: LogMessageLevel, category: String) {
        self.message = message
        self.level = level
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case message = "m"
        case level = "l"
        case category = "c"
    }
}

nonisolated struct LogNetworkPayload: Codable, Hashable, Sendable {
    let url: String
    let method: String
    let requestHeaders: [String: String]
    let responseHeaders: [String: String]
    let statusCode: Int
    let responseBody: Data

    init(
        url: String,
        method: String,
        requestHeaders: [String: String],
        responseHeaders: [String: String],
        statusCode: Int,
        responseBody: Data
    ) {
        self.url = url
        self.method = method
        self.requestHeaders = requestHeaders
        self.responseHeaders = responseHeaders
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    init(
        url: URL,
        method: String,
        requestHeaders: [String: String],
        responseHeaders: [String: String],
        statusCode: Int,
        responseBody: Data
    ) {
        self.init(
            url: url.absoluteString,
            method: method,
            requestHeaders: requestHeaders,
            responseHeaders: responseHeaders,
            statusCode: statusCode,
            responseBody: responseBody
        )
    }

    enum CodingKeys: String, CodingKey {
        case url = "u"
        case method = "m"
        case requestHeaders = "qh"
        case responseHeaders = "sh"
        case statusCode = "sc"
        case responseBody = "rb"
    }
}

nonisolated enum DecodedLogPacket: Sendable {
    case message(packet: LogPacket, payload: LogMessagePayload)
    case network(packet: LogPacket, payload: LogNetworkPayload)
}

extension Data {
    nonisolated func logViewerPreview(limit: Int = 512) -> String {
        guard !isEmpty else {
            return "<empty>"
        }

        let prefixData = prefix(limit)

        if let preview = String(data: prefixData, encoding: .utf8), !preview.isEmpty {
            return count > limit ? "\(preview)…" : preview
        }

        return "<binary \(count) bytes>"
    }
}
