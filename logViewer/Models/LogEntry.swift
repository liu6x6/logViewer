import SwiftUI

enum LogCategory: String, CaseIterable, Hashable, Identifiable {
    case messages = "Messages"
    case network = "Network"

    var id: String {
        rawValue
    }

    var symbolName: String {
        switch self {
        case .messages:
            return "text.bubble"
        case .network:
            return "network"
        }
    }
}

enum LogSeverity: String, Hashable {
    case debug
    case info
    case warning
    case error

    var color: Color {
        switch self {
        case .debug:
            return .secondary
        case .info:
            return .blue
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }
}

struct LogEntry: Identifiable, Hashable {
    let id: String
    let category: LogCategory
    let title: String
    let summary: String
    let timestamp: Date
    let severity: LogSeverity
    let source: String
    let requestPreview: String
    let responsePreview: String
    let metricsPreview: String

    static func samples(for device: DeviceModel?, category: LogCategory? = nil) -> [LogEntry] {
        let deviceName = device?.name ?? "当前设备"

        let entries = [
            LogEntry(
                id: "messages-app-boot",
                category: .messages,
                title: "App Boot Completed",
                summary: "\(deviceName) 已完成启动流程，实时日志通道已建立。",
                timestamp: .now.addingTimeInterval(-64),
                severity: .info,
                source: "AppLifecycle",
                requestPreview: """
                GET /bootstrap/config
                Host: mobile-api.internal
                X-Device-Name: \(deviceName)
                """,
                responsePreview: """
                200 OK
                {
                  "features": ["messages", "network", "export"]
                }
                """,
                metricsPreview: """
                Duration: 82 ms
                Payload: 2.1 KB
                Source: AppLifecycle
                """
            ),
            LogEntry(
                id: "messages-auth-refresh",
                category: .messages,
                title: "Token Refreshed",
                summary: "认证模块刷新访问令牌，并继续推送新的业务日志。",
                timestamp: .now.addingTimeInterval(-148),
                severity: .debug,
                source: "Authentication",
                requestPreview: """
                POST /auth/refresh
                Authorization: Bearer <redacted>
                """,
                responsePreview: """
                204 No Content
                New expiration: +3600s
                """,
                metricsPreview: """
                Duration: 37 ms
                Queue: background
                Retries: 0
                """
            ),
            LogEntry(
                id: "messages-sync-warning",
                category: .messages,
                title: "Sync Delayed",
                summary: "本地任务同步出现排队，延迟高于预期阈值。",
                timestamp: .now.addingTimeInterval(-302),
                severity: .warning,
                source: "SyncEngine",
                requestPreview: """
                POST /sync/batch
                Items: 143
                Priority: user-initiated
                """,
                responsePreview: """
                202 Accepted
                Server enqueued batch for deferred processing.
                """,
                metricsPreview: """
                Duration: 641 ms
                Queue wait: 411 ms
                Upload: 38 KB
                """
            ),
            LogEntry(
                id: "network-feed-request",
                category: .network,
                title: "GET /v1/feed",
                summary: "时间线接口返回成功，数据刷新完成。",
                timestamp: .now.addingTimeInterval(-18),
                severity: .info,
                source: "URLSession",
                requestPreview: """
                GET https://api.example.com/v1/feed?limit=20
                Accept: application/json
                User-Agent: logViewer-demo/1.0
                """,
                responsePreview: """
                200 OK
                Content-Type: application/json
                Body size: 18.4 KB
                """,
                metricsPreview: """
                Total: 124 ms
                DNS: 8 ms
                TLS: 21 ms
                Download: 54 ms
                """
            ),
            LogEntry(
                id: "network-upload-failure",
                category: .network,
                title: "POST /v1/upload",
                summary: "上传请求因网关超时失败，等待重试。",
                timestamp: .now.addingTimeInterval(-236),
                severity: .error,
                source: "UploadService",
                requestPreview: """
                POST https://api.example.com/v1/upload
                Content-Type: multipart/form-data
                Payload: 5.6 MB
                """,
                responsePreview: """
                504 Gateway Timeout
                {
                  "message": "upstream timeout"
                }
                """,
                metricsPreview: """
                Total: 4.82 s
                Upload: 4.41 s
                Retry policy: exponential-backoff
                """
            ),
            LogEntry(
                id: "network-image-cache",
                category: .network,
                title: "GET /v1/image/hero",
                summary: "图片资源命中 CDN，首屏加载保持稳定。",
                timestamp: .now.addingTimeInterval(-486),
                severity: .debug,
                source: "ImagePipeline",
                requestPreview: """
                GET https://cdn.example.com/v1/image/hero
                If-None-Match: "hero-42"
                """,
                responsePreview: """
                304 Not Modified
                Served from edge cache
                """,
                metricsPreview: """
                Total: 29 ms
                Cache: HIT
                Transfer size: 0 B
                """
            )
        ]

        guard let category else {
            return entries
        }

        return entries.filter { $0.category == category }
    }
}
