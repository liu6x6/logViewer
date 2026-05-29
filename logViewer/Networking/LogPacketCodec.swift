import Foundation

nonisolated enum LogPacketCodingError: LocalizedError {
    case unsupportedPacketType(Int)
    case packetTypeMismatch(expected: LogPacketType, actual: Int)
    case unsupportedVersion(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedPacketType(let rawValue):
            return "Unsupported log packet type: \(rawValue)"
        case .packetTypeMismatch(let expected, let actual):
            return "Packet type mismatch. Expected \(expected.rawValue), received \(actual)."
        case .unsupportedVersion(let version):
            return "Unsupported log packet version: \(version)"
        }
    }
}

/// Binary PropertyList keeps payloads compact and preserves nested `Data` without base64 expansion.
nonisolated final class LogPacketEncoder {
    let protocolVersion: String

    private let envelopeEncoder: PropertyListEncoder
    private let payloadEncoder: PropertyListEncoder

    init(protocolVersion: String = LogPacket.currentVersion) {
        self.protocolVersion = protocolVersion

        let envelopeEncoder = PropertyListEncoder()
        envelopeEncoder.outputFormat = .binary
        self.envelopeEncoder = envelopeEncoder

        let payloadEncoder = PropertyListEncoder()
        payloadEncoder.outputFormat = .binary
        self.payloadEncoder = payloadEncoder
    }

    func encodeLogMessage(
        _ payload: LogMessagePayload,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws -> Data {
        try encodePayload(payload, packetType: .message, timestamp: timestamp)
    }

    func encodeNetworkSummary(
        _ payload: LogNetworkPayload,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws -> Data {
        try encodePayload(payload, packetType: .networkSummary, timestamp: timestamp)
    }

    func encodePayload<Payload: Encodable>(
        _ payload: Payload,
        packetType: LogPacketType,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws -> Data {
        let packet = try makePacket(payload, packetType: packetType, timestamp: timestamp)
        return try envelopeEncoder.encode(packet)
    }

    func makePacket<Payload: Encodable>(
        _ payload: Payload,
        packetType: LogPacketType,
        timestamp: TimeInterval = Date().timeIntervalSince1970
    ) throws -> LogPacket {
        let payloadData = try payloadEncoder.encode(payload)

        return LogPacket(
            version: protocolVersion,
            timestamp: timestamp,
            packetType: packetType,
            payload: payloadData
        )
    }
}

nonisolated final class LogPacketDecoder {
    let supportedVersion: String?

    private let envelopeDecoder: PropertyListDecoder
    private let payloadDecoder: PropertyListDecoder

    init(supportedVersion: String? = LogPacket.currentVersion) {
        self.supportedVersion = supportedVersion
        self.envelopeDecoder = PropertyListDecoder()
        self.payloadDecoder = PropertyListDecoder()
    }

    func decodePacket(from data: Data) throws -> LogPacket {
        let packet = try envelopeDecoder.decode(LogPacket.self, from: data)

        if let supportedVersion, packet.version != supportedVersion {
            throw LogPacketCodingError.unsupportedVersion(packet.version)
        }

        return packet
    }

    func decodeLogMessage(from packet: LogPacket) throws -> LogMessagePayload {
        try decodePayload(LogMessagePayload.self, from: packet, expectedType: .message)
    }

    func decodeNetworkSummary(from packet: LogPacket) throws -> LogNetworkPayload {
        try decodePayload(LogNetworkPayload.self, from: packet, expectedType: .networkSummary)
    }

    func decodePayload<Payload: Decodable>(
        _ payloadType: Payload.Type,
        from packet: LogPacket,
        expectedType: LogPacketType? = nil
    ) throws -> Payload {
        if let expectedType, packet.packetType != expectedType.rawValue {
            throw LogPacketCodingError.packetTypeMismatch(expected: expectedType, actual: packet.packetType)
        }

        return try payloadDecoder.decode(payloadType, from: packet.payload)
    }

    func decodeEnvelopeAndPayload(from data: Data) throws -> DecodedLogPacket {
        let packet = try decodePacket(from: data)

        guard let packetType = packet.type else {
            throw LogPacketCodingError.unsupportedPacketType(packet.packetType)
        }

        switch packetType {
        case .message:
            return .message(packet: packet, payload: try decodeLogMessage(from: packet))
        case .networkSummary:
            return .network(packet: packet, payload: try decodeNetworkSummary(from: packet))
        }
    }
}
