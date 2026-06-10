import Foundation

enum NetworkResponseBodyNormalizer {
    static func normalized(
        _ data: Data?,
        headers: [String: String]? = nil,
        contentType: String? = nil
    ) -> Data? {
        guard let data, !data.isEmpty else {
            return data
        }

        guard shouldInspectForRepeatedJSON(in: data, headers: headers, contentType: contentType) else {
            return data
        }

        if let deduplicatedHalf = deduplicatedExactHalf(in: data) {
            return deduplicatedHalf
        }

        if let deduplicatedText = deduplicatedRepeatedJSONText(in: data) {
            return deduplicatedText
        }

        return data
    }

    private static func shouldInspectForRepeatedJSON(
        in data: Data,
        headers: [String: String]?,
        contentType: String?
    ) -> Bool {
        if let resolvedContentType = resolvedContentType(headers: headers, contentType: contentType),
           resolvedContentType.contains("json") {
            return true
        }

        guard let decodedText = decodedText(from: data) else {
            return false
        }

        let trimmedText = decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedText.hasPrefix("{") || trimmedText.hasPrefix("[")
    }

    private static func resolvedContentType(headers: [String: String]?, contentType: String?) -> String? {
        if let contentType, !contentType.isEmpty {
            return normalizedContentTypeValue(contentType)
        }

        let headerValue = headers?.first { key, _ in
            key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value

        guard let headerValue else {
            return nil
        }

        return normalizedContentTypeValue(headerValue)
    }

    private static func normalizedContentTypeValue(_ value: String) -> String {
        value
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? value.lowercased()
    }

    private static func deduplicatedExactHalf(in data: Data) -> Data? {
        guard data.count.isMultiple(of: 2) else {
            return nil
        }

        let midpoint = data.count / 2
        let firstHalf = Data(data.prefix(midpoint))
        let secondHalf = data.suffix(midpoint)

        guard firstHalf.elementsEqual(secondHalf), isValidJSON(firstHalf) else {
            return nil
        }

        return firstHalf
    }

    private static func deduplicatedRepeatedJSONText(in data: Data) -> Data? {
        guard let decodedText = decodedText(from: data) else {
            return nil
        }

        let trimmedText = decodedText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return nil
        }

        let fullRange = NSRange(trimmedText.startIndex..<trimmedText.endIndex, in: trimmedText)
        guard
            let match = duplicatedPayloadPattern.firstMatch(in: trimmedText, range: fullRange),
            let captureRange = Range(match.range(at: 1), in: trimmedText)
        else {
            return nil
        }

        let candidate = String(trimmedText[captureRange])
        guard
            let candidateData = candidate.data(using: .utf8),
            isValidJSON(candidateData)
        else {
            return nil
        }

        return candidateData
    }

    private static func decodedText(from data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8), !utf8.isEmpty {
            return utf8
        }

        if let unicode = String(data: data, encoding: .unicode), !unicode.isEmpty {
            return unicode
        }

        return nil
    }

    private static func isValidJSON(_ data: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])) != nil
    }

    private static let duplicatedPayloadPattern = try! NSRegularExpression(pattern: #"(?s)^(.+?)\s*\1$"#)
}
