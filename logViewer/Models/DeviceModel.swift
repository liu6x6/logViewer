import SwiftUI

enum DevicePlatform: String, Codable, CaseIterable, Hashable {
    case ios
    case android

    var title: String {
        switch self {
        case .ios:
            return "iOS"
        case .android:
            return "Android"
        }
    }

    var symbolName: String {
        switch self {
        case .ios:
            return "iphone.gen3"
        case .android:
            return "candybarphone"
        }
    }
}

enum DeviceConnectionStatus: String, Codable, CaseIterable, Hashable {
    case connected = "已连接"
    case disconnected = "未连接"

    var title: String {
        rawValue
    }

    var symbolName: String {
        switch self {
        case .connected:
            return "checkmark.circle.fill"
        case .disconnected:
            return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .connected:
            return .green
        case .disconnected:
            return .secondary
        }
    }
}

struct ConnectionRecord: Identifiable, Hashable {
    let id: String
    let timestamp: Date
    let note: String
}

/// Rich metadata about a connected device, gathered from each transport's
/// handshake / discovery info. Every field is optional because not all
/// transports expose the same level of detail (e.g. MultipeerConnectivity
/// only gives a display name unless the sender advertises more).
struct DeviceDetails: Hashable, Sendable {
    var model: String?
    var systemName: String?
    var systemVersion: String?
    var appName: String?
    var appVersion: String?

    var isEmpty: Bool {
        model == nil && systemName == nil && systemVersion == nil && appName == nil && appVersion == nil
    }
}

struct DeviceModel: Identifiable, Hashable {
    let id: String
    var name: String
    var platform: DevicePlatform
    var status: DeviceConnectionStatus
    var transferRateKBps: Double
    var connectionHistory: [ConnectionRecord]
    var details: DeviceDetails

    init(
        id: String,
        name: String,
        platform: DevicePlatform = .ios,
        status: DeviceConnectionStatus = .disconnected,
        transferRateKBps: Double = 0,
        connectionHistory: [ConnectionRecord] = [],
        details: DeviceDetails = DeviceDetails()
    ) {
        self.id = id
        self.name = name
        self.platform = platform
        self.status = status
        self.transferRateKBps = transferRateKBps
        self.connectionHistory = connectionHistory
        self.details = details
    }

    /// e.g. "iPhone 14 Pro" — falls back to a system summary when no model is known.
    var modelSummary: String? {
        if let model = details.model, !model.isEmpty {
            return model
        }
        return systemSummary
    }

    /// e.g. "iOS 17.4" or "Android 14".
    var systemSummary: String? {
        let name = details.systemName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = details.systemVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch (name.isEmpty, version.isEmpty) {
        case (false, false):
            return "\(name) \(version)"
        case (false, true):
            return name
        case (true, false):
            return version
        case (true, true):
            return nil
        }
    }

    /// e.g. "MyApp 1.2.0".
    var appSummary: String? {
        let name = details.appName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let version = details.appVersion?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        switch (name.isEmpty, version.isEmpty) {
        case (false, false):
            return "\(name) \(version)"
        case (false, true):
            return name
        case (true, false):
            return version
        case (true, true):
            return nil
        }
    }

    var transferRateText: String {
        guard status == .connected else {
            return "0 KB/s"
        }

        if transferRateKBps >= 1024 {
            return String(format: "%.2f MB/s", transferRateKBps / 1024)
        }

        return String(format: "%.0f KB/s", transferRateKBps)
    }

    var historySummary: String {
        let formatter = Date.FormatStyle()
            .month(.abbreviated)
            .day()
            .hour(.twoDigits(amPM: .omitted))
            .minute(.twoDigits)

        if let latest = connectionHistory.first {
            return "连接历史 \(connectionHistory.count) 次 · 最近 \(latest.timestamp.formatted(formatter))"
        }

        return "暂无连接历史"
    }

    var recentHistory: [ConnectionRecord] {
        Array(connectionHistory.prefix(2))
    }

    mutating func appendHistory(note: String, timestamp: Date = .now) {
        connectionHistory.insert(
            ConnectionRecord(
                id: "\(id)-\(timestamp.timeIntervalSince1970)",
                timestamp: timestamp,
                note: note
            ),
            at: 0
        )
    }

    /// Overlays non-empty detail fields onto the current details.
    mutating func mergeDetails(_ newDetails: DeviceDetails?) {
        guard let newDetails, !newDetails.isEmpty else {
            return
        }

        if let model = newDetails.model { details.model = model }
        if let systemName = newDetails.systemName { details.systemName = systemName }
        if let systemVersion = newDetails.systemVersion { details.systemVersion = systemVersion }
        if let appName = newDetails.appName { details.appName = appName }
        if let appVersion = newDetails.appVersion { details.appVersion = appVersion }
    }
}
