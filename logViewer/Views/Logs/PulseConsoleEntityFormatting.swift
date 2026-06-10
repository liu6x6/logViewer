import Foundation
import SwiftUI

#if os(macOS) && canImport(Pulse)
import Pulse

enum NetworkRequestReplayError: LocalizedError {
    case invalidURL(String?)
    case blockedURL(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let rawValue):
            if let rawValue, !rawValue.isEmpty {
                return "This request can't be sent again because its URL is invalid: \(rawValue)"
            }
            return "This request can't be sent again because it does not contain a valid URL."
        case .blockedURL(let rawValue):
            return "This request is blocked by the current network blocklist and was not sent: \(rawValue)"
        }
    }
}

enum NetworkRequestCopyAction: String, CaseIterable, Identifiable {
    case url
    case queryParameters
    case queryParametersJSON
    case headers
    case headersJSON
    case body
    case bodyPrettyJSON
    case cURL
    case requestSummary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .url:
            return "Copy URL"
        case .queryParameters:
            return "Copy Query Parameters"
        case .queryParametersJSON:
            return "Copy Query Parameters as JSON"
        case .headers:
            return "Copy Headers"
        case .headersJSON:
            return "Copy Headers as JSON"
        case .body:
            return "Copy Body"
        case .bodyPrettyJSON:
            return "Copy Body as Pretty JSON"
        case .cURL:
            return "Copy cURL"
        case .requestSummary:
            return "Copy Request Summary"
        }
    }

    var systemImage: String {
        switch self {
        case .url:
            return "link"
        case .queryParameters:
            return "list.bullet.indent"
        case .queryParametersJSON:
            return "curlybraces.square"
        case .headers:
            return "rectangle.compress.vertical"
        case .headersJSON:
            return "shippingbox"
        case .body:
            return "doc.text"
        case .bodyPrettyJSON:
            return "doc.plaintext"
        case .cURL:
            return "terminal"
        case .requestSummary:
            return "doc.on.doc"
        }
    }

    func text(from task: NetworkTaskEntity) -> String? {
        switch self {
        case .url:
            return task.copyableRequestURLText
        case .queryParameters:
            return task.requestQueryParametersText
        case .queryParametersJSON:
            return task.requestQueryParametersJSONText
        case .headers:
            return task.requestHeadersCopyText
        case .headersJSON:
            return task.requestHeadersJSONText
        case .body:
            return task.requestBodyCopyText
        case .bodyPrettyJSON:
            return task.requestBodyPrettyJSONText
        case .cURL:
            return task.curlCommandText
        case .requestSummary:
            return task.requestSummaryText
        }
    }
}

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
    var canSendAgain: Bool {
        (try? makeReplayRequest()) != nil
    }

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

    var requestHeadersCopyText: String? {
        requestHeaders.isEmpty ? nil : requestHeadersText
    }

    var requestHeaderCount: Int {
        (currentRequest?.headers ?? originalRequest?.headers ?? [:]).count
    }

    var requestHeaderNamesText: String? {
        guard !requestHeaders.isEmpty else {
            return nil
        }
        return requestHeaders.keys
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .joined(separator: "\n")
    }

    var requestHeadersJSONText: String? {
        guard !requestHeaders.isEmpty else {
            return nil
        }
        return formattedJSONString(from: requestHeaders)
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
        renderedBodyText(from: responseBodyData, fallbackSize: responseBodySize)
    }

    var requestBodyData: Data? {
        requestBody?.data
    }

    var requestBodyCopyText: String? {
        decodedRequestText(from: requestBodyData)
    }

    var requestBodyPrettyJSONText: String? {
        guard let data = requestBodyData else {
            return nil
        }
        return prettyJSONString(from: data)
    }

    var copyableRequestURLText: String? {
        guard let rawURL = url?.trimmingCharacters(in: .whitespacesAndNewlines), !rawURL.isEmpty else {
            return nil
        }
        return rawURL
    }

    var requestHostText: String? {
        requestURLComponents?.host ?? host
    }

    var requestPathText: String? {
        let pathValue = requestURLComponents?.percentEncodedPath
        if let pathValue, !pathValue.isEmpty {
            return pathValue
        }
        return nil
    }

    var requestQueryStringText: String? {
        guard let query = requestURLComponents?.percentEncodedQuery, !query.isEmpty else {
            return nil
        }
        return query
    }

    var requestQueryParametersText: String? {
        guard !requestQueryItems.isEmpty else {
            return nil
        }

        return requestQueryItems
            .map { item in
                if let value = item.value {
                    return "\(item.name)=\(value)"
                }
                return item.name
            }
            .joined(separator: "\n")
    }

    var requestQueryParametersJSONText: String? {
        let jsonObject = requestQueryJSONObject
        guard !jsonObject.isEmpty else {
            return nil
        }
        return formattedJSONString(from: jsonObject)
    }

    var curlCommandText: String {
        let methodValue = (httpMethod?.isEmpty == false ? httpMethod! : "GET").uppercased()
        let requestURL = primaryURLText == "Unknown Request" ? "" : primaryURLText
        let headers = requestHeaders
            .sorted { lhs, rhs in lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending }

        var lines = ["curl \(requestURL.shellQuotedForBash)"]
        lines.append("  -X \(methodValue.shellQuotedForBash)")

        for (name, value) in headers {
            lines.append("  -H \(("\(name): \(value)").shellQuotedForBash)")
        }

        if let requestBodyText = decodedRequestText(from: requestBodyData), !requestBodyText.isEmpty {
            lines.append("  --data-raw \(requestBodyText.shellQuotedForBash)")
        }

        return lines.joined(separator: " \\\n")
    }

    func makeReplayRequest() throws -> URLRequest {
        guard
            let rawURL = url?.trimmingCharacters(in: .whitespacesAndNewlines),
            !rawURL.isEmpty,
            let replayURL = URL(string: rawURL)
        else {
            throw NetworkRequestReplayError.invalidURL(url)
        }

        var request = URLRequest(url: replayURL)
        request.httpMethod = (httpMethod?.isEmpty == false ? httpMethod! : "GET").uppercased()

        let headers = replayHeaders
        request.allHTTPHeaderFields = headers.isEmpty ? nil : headers
        request.httpBody = requestBodyData
        request.timeoutInterval = 60
        return request
    }

    var replayTaskDescription: String {
        let methodValue = (httpMethod?.isEmpty == false ? httpMethod! : "GET").uppercased()
        let timestamp = Self.replayTimestampFormatter.string(from: Date())
        return "Inspector Replay @ \(timestamp) · \(methodValue) \(primaryURLText)"
    }

    var shareableResponseText: String? {
        if let prettyJSON = prettyPrintedResponseJSON {
            return prettyJSON
        }
        return decodedResponseText
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

    var normalizedHostValue: String? {
        if let host, let normalizedHost = NetworkRequestBlocklist.normalizedHost(host) {
            return normalizedHost
        }
        return url.flatMap(NetworkRequestBlocklist.normalizedHost)
    }

    var normalizedURLValue: String? {
        NetworkRequestBlocklist.normalizedURL(url ?? "")
    }

    var responseBodyData: Data? {
        NetworkResponseBodyNormalizer.normalized(
            responseBody?.data,
            headers: response?.headers,
            contentType: responseContentType
        )
    }

    var responseContentTypeValue: NetworkLogger.ContentType? {
        responseBody?.contentType
            ?? response?.contentType
            ?? responseContentType.flatMap(NetworkLogger.ContentType.init)
    }

    var prettyPrintedResponseJSON: String? {
        guard let data = responseBodyData else {
            return nil
        }
        return prettyJSONString(from: data)
    }

    var decodedResponseText: String? {
        decodedRequestText(from: responseBodyData)
    }

    var requestSummaryText: String {
        [
            "\(requestMethodValue) \(primaryURLText)",
            "",
            "Headers",
            requestHeadersText,
            "",
            "Query Parameters",
            requestQueryParametersText ?? "No Query Parameters",
            "",
            "Body",
            requestBodyPrettyJSONText ?? requestBodyCopyText ?? "No Body"
        ]
        .joined(separator: "\n")
    }

    var binaryResponseSummary: String {
        let sizeDescription = Int64(responseBodyData?.count ?? Int(responseBodySize)).byteCountString
        let contentTypeDescription = responseContentTypeValue?.rawValue ?? "unknown content type"
        return "Binary response captured (\(sizeDescription), \(contentTypeDescription)). Use Save Response to export the original body."
    }

    private var requestMethodValue: String {
        (httpMethod?.isEmpty == false ? httpMethod! : "GET").uppercased()
    }

    private var requestHeaders: [String: String] {
        currentRequest?.headers ?? originalRequest?.headers ?? [:]
    }

    private var requestURLComponents: URLComponents? {
        guard let copyableRequestURLText else {
            return nil
        }
        return URLComponents(string: copyableRequestURLText)
    }

    private var requestQueryItems: [URLQueryItem] {
        requestURLComponents?.queryItems ?? []
    }

    private var requestQueryJSONObject: [String: Any] {
        var result: [String: Any] = [:]

        for item in requestQueryItems {
            let value = item.value ?? ""
            if let existingValues = result[item.name] as? [String] {
                result[item.name] = existingValues + [value]
            } else if let existingValue = result[item.name] as? String {
                result[item.name] = [existingValue, value]
            } else {
                result[item.name] = value
            }
        }

        return result
    }

    private func formattedJSONString(from object: Any) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
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
            if let decodedText = decodedRequestText(from: data) {
                return decodedText
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

    private func decodedRequestText(from data: Data?) -> String? {
        guard let data else {
            return nil
        }

        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }

        if let unicode = String(data: data, encoding: .unicode), !unicode.isEmpty {
            return unicode
        }

        return nil
    }

    private var replayHeaders: [String: String] {
        let droppedHeaders: Set<String> = [
            "connection",
            "content-length",
            "host",
            "proxy-connection",
            "transfer-encoding"
        ]

        return (currentRequest?.headers ?? originalRequest?.headers ?? [:]).reduce(into: [:]) { result, header in
            guard !droppedHeaders.contains(header.key.lowercased()) else {
                return
            }
            result[header.key] = header.value
        }
    }

    private static let replayTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

extension Int64 {
    var byteCountString: String {
        guard self >= 0 else {
            return "Unknown"
        }
        return ByteCountFormatter.string(fromByteCount: self, countStyle: .binary)
    }
}

private extension String {
    var shellQuotedForBash: String {
        "'" + replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
#endif
