import Foundation
import SwiftUI

#if os(macOS) && canImport(Pulse)
import Pulse

extension LoggerMessageEntity {
    var logLevelTitle: String {
        (LoggerStore.Level(rawValue: level) ?? .debug).name.uppercased()
    }

    var logLevelColor: Color {
        switch LoggerStore.Level(rawValue: level) ?? .debug {
        case .trace:
            return .secondary
        case .debug:
            return .blue
        case .info:
            return .primary
        case .notice:
            return .mint
        case .warning:
            return .orange
        case .error:
            return .red
        case .critical:
            return .purple
        }
    }

    var metadataText: String {
        guard !metadata.isEmpty else {
            return ""
        }
        return metadata
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}

extension NetworkTaskEntity {
    var primaryURLText: String {
        if let url, !url.isEmpty {
            return url
        }
        if let host, let path, !host.isEmpty {
            return host + path
        }
        return "Unknown Request"
    }

    var secondaryNetworkSummary: String {
        let parts = [
            host.flatMap { $0.isEmpty ? nil : $0 },
            response?.contentType?.type,
            errorSummary == "None" ? nil : errorSummary
        ].compactMap { $0 }

        return parts.isEmpty ? "No additional metadata" : parts.joined(separator: " • ")
    }

    var statusDisplayText: String {
        if statusCode > 0 {
            return "\(statusCode)"
        }
        switch state {
        case .pending:
            return "Pending"
        case .success:
            return "Success"
        case .failure:
            return "Failed"
        }
    }

    var statusAccentColor: Color {
        switch state {
        case .pending:
            return .orange
        case .success:
            if statusCode >= 400 {
                return .red
            }
            if statusCode >= 300 {
                return .orange
            }
            return .green
        case .failure:
            return .red
        }
    }

    var durationText: String {
        guard duration > 0 else {
            return "—"
        }
        if duration < 1 {
            return "\(Int(duration * 1000)) ms"
        }
        return String(format: "%.2f s", duration)
    }

    var requestHeadersText: String {
        formattedHeaders(from: currentRequest?.headers ?? originalRequest?.headers ?? [:])
    }

    var responseHeadersText: String {
        formattedHeaders(from: response?.headers ?? [:])
    }

    var responseHeaderSummary: String {
        let headers = response?.headers ?? [:]
        guard !headers.isEmpty else {
            return "No Headers"
        }
        return "\(headers.count) Headers"
    }

    var requestBodyPreviewText: String {
        renderedBodyText(from: requestBody?.data, fallbackSize: requestBodySize)
    }

    var responseBodyText: String {
        renderedBodyText(from: responseBody?.data, fallbackSize: responseBodySize)
    }

    var shareableResponseText: String {
        responseBodyText
    }

    var errorSummary: String {
        if let errorDebugDescription, !errorDebugDescription.isEmpty {
            return errorDebugDescription
        }
        if let errorDomain, !errorDomain.isEmpty {
            return "\(errorDomain) (\(errorCode))"
        }
        if let error {
            return String(describing: error)
        }
        return "None"
    }

    private func formattedHeaders(from headers: [String: String]) -> String {
        guard !headers.isEmpty else {
            return "No Headers"
        }
        return headers
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    private func renderedBodyText(from data: Data?, fallbackSize: Int64) -> String {
        if let data, !data.isEmpty {
            if let prettyJSON = prettyJSONString(from: data) {
                return prettyJSON
            }
            if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
                return utf8
            }
            return "Binary payload (\(fallbackSize.byteCountString))"
        }
        if fallbackSize > 0 {
            return "Body not materialized (\(fallbackSize.byteCountString))"
        }
        return "No Body"
    }

    private func prettyJSONString(from data: Data) -> String? {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            JSONSerialization.isValidJSONObject(object),
            let formatted = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: formatted, encoding: .utf8)
        else {
            return nil
        }
        return string
    }
}

extension Int64 {
    var byteCountString: String {
        guard self >= 0 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .binary)
    }
}
#endif
