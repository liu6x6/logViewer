import SwiftUI

#if os(macOS) && canImport(Pulse)
import Pulse

extension LoggerMessageEntity {
    var logLevelTitle: String {
        switch LoggerStore.Level(rawValue: level) ?? .debug {
        case .trace:
            return "TRACE"
        case .debug:
            return "DEBUG"
        case .info:
            return "INFO"
        case .notice:
            return "NOTICE"
        case .warning:
            return "WARNING"
        case .error:
            return "ERROR"
        case .critical:
            return "CRITICAL"
        }
    }

    var logLevelColor: Color {
        switch LoggerStore.Level(rawValue: level) ?? .debug {
        case .trace, .debug:
            return .secondary
        case .info, .notice:
            return .blue
        case .warning:
            return .orange
        case .error, .critical:
            return .red
        }
    }

    var metadataText: String {
        metadata
            .sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "\n")
    }
}

extension NetworkTaskEntity {
    var primaryURLText: String {
        path ?? url ?? "Unknown URL"
    }

    var secondaryNetworkSummary: String {
        var parts: [String] = []

        if let host, !host.isEmpty {
            parts.append(host)
        }
        if let contentType = response?.contentType?.type {
            parts.append(contentType)
        }
        if isFromCache {
            parts.append("Cache")
        }
        if let errorDomain, !errorDomain.isEmpty {
            parts.append(errorDomain)
        }

        return parts.isEmpty ? "Waiting for response details" : parts.joined(separator: " · ")
    }

    var statusDisplayText: String {
        switch state {
        case .pending:
            return "PENDING"
        case .success:
            return statusCode > 0 ? "\(statusCode)" : "SUCCESS"
        case .failure:
            return statusCode > 0 ? "\(statusCode)" : "FAILED"
        }
    }

    var statusAccentColor: Color {
        switch state {
        case .pending:
            return .orange
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    var responseHeaderSummary: String {
        let count = response?.headers.count ?? 0
        return "\(count) headers"
    }

    var requestHeadersText: String {
        originalRequest?.headers.formattedHeaderBlock ?? "No request headers"
    }

    var responseHeadersText: String {
        response?.headers.formattedHeaderBlock ?? "No response headers"
    }

    var requestBodyPreviewText: String {
        requestBody?.data?.logViewerPreview(limit: 2_048) ?? "No request body"
    }

    var responseBodyPreviewText: String {
        responseBody?.data?.logViewerPreview(limit: 4_096) ?? "No response body"
    }

    var durationText: String {
        guard duration > 0 else {
            return "Unavailable"
        }

        if duration >= 1 {
            return String(format: "%.2f s", duration)
        }

        return String(format: "%.0f ms", duration * 1_000)
    }

    var errorSummary: String {
        if let errorDebugDescription, !errorDebugDescription.isEmpty {
            return errorDebugDescription
        }
        if let errorDomain, !errorDomain.isEmpty {
            return "\(errorDomain) (\(errorCode))"
        }
        return state == .failure ? "Request failed" : "None"
    }
}

extension Dictionary where Key == String, Value == String {
    var formattedHeaderBlock: String {
        guard !isEmpty else {
            return "No headers"
        }

        return sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }
}

extension Int64 {
    var byteCountString: String {
        guard self > 0 else {
            return "0 B"
        }
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .binary)
    }
}
#endif
