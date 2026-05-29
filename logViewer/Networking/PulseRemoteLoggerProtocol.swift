#if os(macOS) && canImport(Pulse)
import Foundation
import Pulse

enum PulseRemoteLoggerPacketCode: UInt8 {
    case clientHello = 0
    case serverHello = 1
    case pause = 2
    case resume = 3
    case ping = 6
    case storeEventMessageStored = 7
    case storeEventNetworkTaskCreated = 8
    case storeEventNetworkTaskProgressUpdated = 9
    case storeEventNetworkTaskCompleted = 10
    case message = 13
}

struct PulseRemoteLoggerClientHello: Decodable, Sendable {
    let version: String?
    let deviceId: UUID
    let deviceInfo: LoggerStore.Info.DeviceInfo
    let appInfo: LoggerStore.Info.AppInfo
}

struct PulseRemoteLoggerServerHello: Encodable, Sendable {
    let version: String
}

struct PulseRemoteLoggerEmpty: Codable, Sendable {}

enum PulseRemoteLoggerPath: Codable, Sendable {
    case updateMocks
    case getMockedResponse(mockID: UUID)
    case openMessageDetails
    case openTaskDetails
}

struct PulseRemoteLoggerMessage: Sendable {
    struct Header {
        let id: UInt32
        let options: Options
        let pathSize: UInt32
        let dataSize: UInt32

        init?(_ data: Data) {
            guard data.count >= PulseRemoteLoggerMessage.headerSize else {
                return nil
            }
            self.id = UInt32(pulseRemoteData: data.pulseRemoteSlice(from: 0, size: 4))
            self.options = Options(rawValue: data[4])
            self.pathSize = UInt32(pulseRemoteData: data.pulseRemoteSlice(from: 5, size: 4))
            self.dataSize = UInt32(pulseRemoteData: data.pulseRemoteSlice(from: 9, size: 4))
        }
    }

    struct Options: OptionSet, Sendable {
        let rawValue: UInt8
        init(rawValue: UInt8) { self.rawValue = rawValue }

        static let response = Options(rawValue: 1 << 0)
    }

    let id: UInt32
    let options: Options
    let path: PulseRemoteLoggerPath
    let data: Data

    private static let headerSize = 13

    static func encode(_ message: PulseRemoteLoggerMessage) throws -> Data {
        let encodedPath = try JSONEncoder().encode(message.path)

        var data = Data()
        data.append(Data(pulseRemoteBigEndian: message.id))
        data.append(message.options.rawValue)
        data.append(Data(pulseRemoteBigEndian: UInt32(encodedPath.count)))
        data.append(Data(pulseRemoteBigEndian: UInt32(message.data.count)))
        data.append(encodedPath)
        data.append(message.data)
        return data
    }

    static func decode(_ data: Data) throws -> PulseRemoteLoggerMessage {
        guard let header = Header(data) else {
            throw PulseRemoteLoggerProtocolError.notEnoughData
        }
        let requiredSize = headerSize + Int(header.pathSize) + Int(header.dataSize)
        guard data.count >= requiredSize else {
            throw PulseRemoteLoggerProtocolError.notEnoughData
        }

        let path = try JSONDecoder().decode(
            PulseRemoteLoggerPath.self,
            from: data.pulseRemoteSlice(from: headerSize, size: Int(header.pathSize))
        )
        let body = data.pulseRemoteSlice(from: headerSize + Int(header.pathSize), size: Int(header.dataSize))
        return PulseRemoteLoggerMessage(id: header.id, options: header.options, path: path, data: body)
    }
}

struct PulseRemoteLoggerWirePacket: Sendable {
    let code: UInt8
    let body: Data
}

enum PulseRemoteLoggerProtocolError: Error {
    case notEnoughData
    case unsupportedContentSize
}

enum PulseRemoteLoggerProtocol {
    static let bonjourService = "_pulse._tcp"
    static let serverVersion = "1.0.0"

    static func encodePacket(code: UInt8, body: Data) throws -> Data {
        guard body.count < UInt32.max else {
            throw PulseRemoteLoggerProtocolError.unsupportedContentSize
        }

        var data = Data()
        data.append(code)
        let compressedBody = try body.pulseRemoteCompressed()
        data.append(Data(pulseRemoteBigEndian: UInt32(compressedBody.count)))
        data.append(compressedBody)
        return data
    }

    static func decodePacket(from buffer: Data) throws -> (PulseRemoteLoggerWirePacket, Int) {
        guard buffer.count >= 5 else {
            throw PulseRemoteLoggerProtocolError.notEnoughData
        }

        let code = buffer[buffer.startIndex]
        let contentSize = UInt32(pulseRemoteData: buffer.pulseRemoteSlice(from: 1, size: 4))
        let packetSize = 5 + Int(contentSize)

        guard buffer.count >= packetSize else {
            throw PulseRemoteLoggerProtocolError.notEnoughData
        }

        let compressedBody = buffer.pulseRemoteSlice(from: 5, size: Int(contentSize))
        let body = try compressedBody.pulseRemoteDecompressed()
        return (PulseRemoteLoggerWirePacket(code: code, body: body), packetSize)
    }

    static func decodeNetworkCompleted(from data: Data) throws -> LoggerStore.Event.NetworkTaskCompleted {
        struct Manifest {
            let messageSize: UInt32
            let requestBodySize: UInt32
            let responseBodySize: UInt32

            static let size = 12

            var totalSize: Int {
                Manifest.size + Int(messageSize) + Int(requestBodySize) + Int(responseBodySize)
            }
        }

        guard data.count >= Manifest.size else {
            throw PulseRemoteLoggerProtocolError.notEnoughData
        }

        let manifest = Manifest(
            messageSize: UInt32(pulseRemoteData: data.pulseRemoteSlice(from: 0, size: 4)),
            requestBodySize: UInt32(pulseRemoteData: data.pulseRemoteSlice(from: 4, size: 4)),
            responseBodySize: UInt32(pulseRemoteData: data.pulseRemoteSlice(from: 8, size: 4))
        )

        guard data.count >= manifest.totalSize else {
            throw PulseRemoteLoggerProtocolError.notEnoughData
        }

        let decodedEvent = try JSONDecoder().decode(
            LoggerStore.Event.NetworkTaskCompleted.self,
            from: data.pulseRemoteSlice(from: Manifest.size, size: Int(manifest.messageSize))
        )

        let requestBodyStart = Manifest.size + Int(manifest.messageSize)
        let requestBody = manifest.requestBodySize > 0
            ? data.pulseRemoteSlice(from: requestBodyStart, size: Int(manifest.requestBodySize))
            : nil

        let responseBodyStart = requestBodyStart + Int(manifest.requestBodySize)
        let responseBody = manifest.responseBodySize > 0
            ? data.pulseRemoteSlice(from: responseBodyStart, size: Int(manifest.responseBodySize))
            : nil

        return LoggerStore.Event.NetworkTaskCompleted(
            taskId: decodedEvent.taskId,
            taskType: decodedEvent.taskType,
            createdAt: decodedEvent.createdAt,
            originalRequest: decodedEvent.originalRequest,
            currentRequest: decodedEvent.currentRequest,
            response: decodedEvent.response,
            error: decodedEvent.error,
            requestBody: requestBody,
            responseBody: responseBody,
            metrics: decodedEvent.metrics,
            label: decodedEvent.label,
            taskDescription: decodedEvent.taskDescription
        )
    }
}

private extension Data {
    init(pulseRemoteBigEndian value: UInt32) {
        var value = value.bigEndian
        self.init(bytes: &value, count: MemoryLayout<UInt32>.size)
    }

    func pulseRemoteSlice(from offset: Int, size: Int) -> Data {
        self[(startIndex + offset) ..< (startIndex + offset + size)]
    }

    func pulseRemoteCompressed() throws -> Data {
        try (self as NSData).compressed(using: .lzfse) as Data
    }

    func pulseRemoteDecompressed() throws -> Data {
        try (self as NSData).decompressed(using: .lzfse) as Data
    }
}

private extension UInt32 {
    init(pulseRemoteData data: Data) {
        var accumulator: UInt64 = 0
        for index in 0..<4 {
            let shift = (3 - index) * 8
            accumulator |= UInt64(data[data.startIndex + index]) << UInt64(shift)
        }
        self = UInt32(accumulator)
    }
}
#endif
