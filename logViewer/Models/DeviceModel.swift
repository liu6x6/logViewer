import SwiftUI

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

struct DeviceModel: Identifiable, Hashable {
    let id: String
    var name: String
    var status: DeviceConnectionStatus
    var transferRateKBps: Double
    var connectionHistory: [ConnectionRecord]

    init(
        id: String,
        name: String,
        status: DeviceConnectionStatus = .disconnected,
        transferRateKBps: Double = 0,
        connectionHistory: [ConnectionRecord] = []
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.transferRateKBps = transferRateKBps
        self.connectionHistory = connectionHistory
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
}
