#if os(macOS)
import Foundation

enum AndroidRemoteLoggerLogLevel: String, Codable, Sendable {
    case debug
    case info
    case error
}

struct AndroidRemoteLoggerHelloPayload: Codable, Sendable {
    let platform: String
    let deviceId: String
    let deviceName: String
    let appId: String
    let appVersion: String
    let osVersion: String
    let sdkVersion: String
}

struct AndroidRemoteLoggerMessagePayload: Codable, Sendable {
    let timestamp: Int64
    let level: AndroidRemoteLoggerLogLevel
    let category: String
    let message: String
    let tag: String?
    let thread: String?
}

struct AndroidRemoteLoggerNetworkCompletedPayload: Codable, Sendable {
    let id: String
    let timestamp: Int64
    let url: String
    let method: String
    let requestHeaders: [String: String]
    let requestBody: String?
    let responseHeaders: [String: String]
    let responseBody: String?
    let statusCode: Int?
    let error: String?
    let durationMs: Int64
}

struct AndroidRemoteLoggerEnvelope: Codable, Sendable {
    let type: String
    let sentAt: Int64
    let hello: AndroidRemoteLoggerHelloPayload?
    let message: AndroidRemoteLoggerMessagePayload?
    let networkCompleted: AndroidRemoteLoggerNetworkCompletedPayload?
}

enum AndroidRemoteLoggerEvent: Sendable {
    case message(AndroidRemoteLoggerMessagePayload)
    case networkCompleted(AndroidRemoteLoggerNetworkCompletedPayload)
}

enum AndroidRemoteLoggerProtocolError: LocalizedError {
    case invalidEnvelopeType(String)
    case missingPayload(String)

    var errorDescription: String? {
        switch self {
        case .invalidEnvelopeType(let type):
            return "Unsupported Android remote logger envelope type: \(type)"
        case .missingPayload(let type):
            return "Android remote logger envelope is missing payload for type \(type)"
        }
    }
}

enum AndroidRemoteLoggerProtocol {
    static let viewerBonjourService = "_logviewer._tcp"
    static let viewerNetServiceType = "_logviewer._tcp."
    static let deviceBonjourService = "_logviewer-android._tcp"
    static let deviceNetServiceType = "_logviewer-android._tcp."

    private static let decoder = JSONDecoder()

    static func decodeEnvelope(from data: Data) throws -> AndroidRemoteLoggerEnvelope {
        try decoder.decode(AndroidRemoteLoggerEnvelope.self, from: data)
    }

    static func decodeEvent(from envelope: AndroidRemoteLoggerEnvelope) throws -> AndroidRemoteLoggerEvent {
        switch envelope.type {
        case "message":
            guard let message = envelope.message else {
                throw AndroidRemoteLoggerProtocolError.missingPayload(envelope.type)
            }
            return .message(message)
        case "networkCompleted":
            guard let networkCompleted = envelope.networkCompleted else {
                throw AndroidRemoteLoggerProtocolError.missingPayload(envelope.type)
            }
            return .networkCompleted(networkCompleted)
        default:
            throw AndroidRemoteLoggerProtocolError.invalidEnvelopeType(envelope.type)
        }
    }
}
#endif
