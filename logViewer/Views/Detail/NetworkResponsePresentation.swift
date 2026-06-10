import AppKit
import Foundation
import Pulse
import SwiftUI

@MainActor
enum NetworkResponseBodyPresentation {
    case empty(message: String)
    case json(text: String, highlightedText: AttributedString)
    case text(text: String)
    case image(preview: NetworkResponseImagePreview)
    case binary(summary: String)

    var copyableText: String? {
        switch self {
        case let .json(text, _), let .text(text):
            return text
        case .empty, .image, .binary:
            return nil
        }
    }

    var bodySummary: String {
        switch self {
        case .empty:
            return "No response body"
        case .json:
            return "Formatted JSON"
        case .text:
            return "Text Body"
        case .image:
            return "Image Preview"
        case .binary:
            return "Binary Payload"
        }
    }
}

struct NetworkResponseImagePreview {
    let image: NSImage
    let data: Data
}

struct NetworkResponseExportPayload {
    let data: Data
    let fileName: String
}

enum NetworkResponseSafariPreviewError: LocalizedError {
    case missingHTMLBody
    case safariUnavailable
    case launchFailed(Int32)

    var errorDescription: String? {
        switch self {
        case .missingHTMLBody:
            return "This response doesn't contain a decodable HTML body."
        case .safariUnavailable:
            return "Safari is not available on this Mac, so the HTML response can't be opened there."
        case .launchFailed(let status):
            return "Safari couldn't open the HTML preview file (exit code \(status))."
        }
    }
}

@MainActor
final class NetworkResponsePreviewCache {
    static let shared = NetworkResponsePreviewCache()

    private let imageCache = NSCache<NSString, NSImage>()
    private var imageDataCache: [String: Data] = [:]

    func imagePreview(for task: NetworkTaskEntity, data: Data) -> NetworkResponseImagePreview? {
        let key = cacheKey(for: task)

        if let cachedImage = imageCache.object(forKey: key as NSString),
           let cachedData = imageDataCache[key] {
            return NetworkResponseImagePreview(image: cachedImage, data: cachedData)
        }

        guard let image = NSImage(data: data) else {
            return nil
        }

        imageCache.setObject(image, forKey: key as NSString)
        imageDataCache[key] = data
        return NetworkResponseImagePreview(image: image, data: data)
    }

    private func cacheKey(for task: NetworkTaskEntity) -> String {
        task.objectID.uriRepresentation().absoluteString
    }
}

final class NetworkResponseHTMLPreviewCache {
    static let shared = NetworkResponseHTMLPreviewCache()

    private let directoryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("logviewer-html-previews", isDirectory: true)

    func previewFileURL(for task: NetworkTaskEntity, data: Data) throws -> URL {
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )

        let objectIDComponent = task.objectID.uriRepresentation()
            .lastPathComponent
            .sanitizedFileNameComponent
        let baseName = task.responseExportBaseName.sanitizedFileNameComponent
        let fileURL = directoryURL.appendingPathComponent(
            "\(baseName)-\(objectIDComponent).html",
            isDirectory: false
        )

        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }
}

@MainActor
extension NetworkTaskEntity {
    var responseBodyPresentation: NetworkResponseBodyPresentation {
        guard let data = responseBodyData, !data.isEmpty else {
            return .empty(message: "No response body was captured for this request.")
        }

        if let jsonText = prettyPrintedResponseJSON {
            return .json(
                text: jsonText,
                highlightedText: JSONSyntaxHighlighter.highlight(jsonText)
            )
        }

        if responseContentTypeValue?.isImage == true,
           let preview = NetworkResponsePreviewCache.shared.imagePreview(for: self, data: data) {
            return .image(preview: preview)
        }

        if let decodedText = decodedResponseText {
            return .text(text: decodedText)
        }

        if let preview = NetworkResponsePreviewCache.shared.imagePreview(for: self, data: data) {
            return .image(preview: preview)
        }

        return .binary(summary: binaryResponseSummary)
    }

    var isHTMLResponse: Bool {
        if responseContentTypeValue?.isHTML == true {
            return decodedResponseText != nil
        }

        guard let text = decodedResponseText else {
            return false
        }

        let trimmedText = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return trimmedText.hasPrefix("<!doctype html")
            || trimmedText.hasPrefix("<html")
            || trimmedText.contains("<body")
            || trimmedText.contains("<head")
    }

    var htmlResponseText: String? {
        guard isHTMLResponse else {
            return nil
        }
        return decodedResponseText
    }

    var responseBodySummaryText: String {
        isHTMLResponse ? "HTML Body" : responseBodyPresentation.bodySummary
    }

    var responseExportPayload: NetworkResponseExportPayload? {
        switch responseBodyPresentation {
        case .empty:
            return nil
        case let .json(text, _):
            guard let data = text.data(using: .utf8) else {
                return nil
            }
            return NetworkResponseExportPayload(data: data, fileName: suggestedResponseFileName(withExtension: "json"))
        case let .text(text):
            guard let data = text.data(using: .utf8) else {
                return nil
            }
            return NetworkResponseExportPayload(data: data, fileName: suggestedResponseFileName(withExtension: suggestedTextFileExtension))
        case let .image(preview):
            return NetworkResponseExportPayload(data: preview.data, fileName: suggestedResponseFileName(withExtension: suggestedImageFileExtension))
        case let .binary(summary: _):
            guard let data = responseBodyData else {
                return nil
            }
            return NetworkResponseExportPayload(data: data, fileName: suggestedResponseFileName(withExtension: suggestedBinaryFileExtension))
        }
    }

    private var suggestedTextFileExtension: String {
        if isHTMLResponse {
            return "html"
        }

        guard let contentType = responseContentTypeValue else {
            return "txt"
        }

        if contentType.type.contains("xml") {
            return "xml"
        }

        return "txt"
    }

    private var suggestedImageFileExtension: String {
        guard let contentType = responseContentTypeValue else {
            return "png"
        }

        switch contentType.lastComponent.lowercased() {
        case "jpeg":
            return "jpg"
        case "":
            return "png"
        default:
            return contentType.lastComponent.lowercased()
        }
    }

    private var suggestedBinaryFileExtension: String {
        guard let contentType = responseContentTypeValue else {
            return "bin"
        }

        let lastComponent = contentType.lastComponent.lowercased()
        return lastComponent.isEmpty ? "bin" : lastComponent
    }

    private func suggestedResponseFileName(withExtension pathExtension: String) -> String {
        let baseName = responseExportBaseName
        return "\(baseName).\(pathExtension)"
    }

    func openHTMLResponseInSafari() throws {
        guard isHTMLResponse, let responseBodyData, !responseBodyData.isEmpty else {
            throw NetworkResponseSafariPreviewError.missingHTMLBody
        }

        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.Safari") != nil else {
            throw NetworkResponseSafariPreviewError.safariUnavailable
        }

        let previewFileURL = try NetworkResponseHTMLPreviewCache.shared.previewFileURL(
            for: self,
            data: responseBodyData
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Safari", previewFileURL.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw NetworkResponseSafariPreviewError.launchFailed(process.terminationStatus)
        }
    }

    var responseExportBaseName: String {
        let timestamp = Self.exportTimestampFormatter.string(from: createdAt)

        if let urlString = url,
           let parsedURL = URL(string: urlString) {
            let lastPathComponent = parsedURL.deletingPathExtension().lastPathComponent
            if !lastPathComponent.isEmpty {
                return "\(lastPathComponent.sanitizedFileNameComponent)-\(timestamp)"
            }

            if let host = parsedURL.host, !host.isEmpty {
                return "\(host.sanitizedFileNameComponent)-\(timestamp)"
            }
        }

        return "response-\(timestamp)"
    }

    private static let exportTimestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}

private enum JSONSyntaxHighlighter {
    static func highlight(_ json: String) -> AttributedString {
        let attributed = NSMutableAttributedString(
            string: json,
            attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
                .foregroundColor: NSColor.labelColor
            ]
        )

        applyPattern(#""(?:\\.|[^"\\])*"(?=\s*:)"#, color: .systemBlue, to: attributed)
        applyPattern(#"(?<=:\s)"(?:\\.|[^"\\])*""#, color: .systemGreen, to: attributed)
        applyPattern(#"\b-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+\-]?\d+)?\b"#, color: .systemPurple, to: attributed)
        applyPattern(#"\b(?:true|false)\b"#, color: .systemOrange, to: attributed)
        applyPattern(#"\bnull\b"#, color: .systemRed, to: attributed)

        return AttributedString(attributed)
    }

    private static func applyPattern(
        _ pattern: String,
        color: NSColor,
        to attributed: NSMutableAttributedString
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return
        }

        let fullRange = NSRange(location: 0, length: attributed.string.utf16.count)
        regex.matches(in: attributed.string, range: fullRange).forEach { match in
            attributed.addAttributes([.foregroundColor: color], range: match.range)
        }
    }
}

private extension String {
    var sanitizedFileNameComponent: String {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed.replacingOccurrences(
            of: #"[^A-Za-z0-9._-]+"#,
            with: "-",
            options: .regularExpression
        )
        let collapsed = replaced.replacingOccurrences(
            of: #"-{2,}"#,
            with: "-",
            options: .regularExpression
        )
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-_."))
    }
}
