import SwiftUI

#if os(macOS) && canImport(Pulse)
import Pulse

struct PulseConsoleHostView: View {
    let injector: PulseStoreInjector
    let category: LogCategory
    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        Group {
            switch category {
            case .messages:
                PulseMessagesConsoleView(selection: $selection)
            case .network:
                PulseNetworkConsoleView(selection: $selection)
            }
        }
        .environment(\.managedObjectContext, injector.store.viewContext)
        .id(category)
    }
}

private struct PulseMessagesConsoleView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\LoggerMessageEntity.createdAt, order: .reverse)],
        predicate: NSPredicate(format: "task == NULL"),
        animation: .default
    )
    private var messages: FetchedResults<LoggerMessageEntity>

    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        if messages.isEmpty {
            PulseEmptyStateView(
                title: "No Messages Yet",
                subtitle: "收到来自 iPhone 的普通日志后，这里会按 Pulse 风格实时追加。"
            )
        } else {
            List(messages, selection: $selection) { message in
                PulseMessageRowView(message: message)
                    .tag(PulseConsoleSelection.message(message.objectID))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

private struct PulseNetworkConsoleView: View {
    @FetchRequest(
        sortDescriptors: [SortDescriptor(\NetworkTaskEntity.createdAt, order: .reverse)],
        animation: .default
    )
    private var tasks: FetchedResults<NetworkTaskEntity>

    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        if tasks.isEmpty {
            PulseEmptyStateView(
                title: "No Network Traffic Yet",
                subtitle: "收到远端网络摘要后，这里会显示请求、状态码、头信息与响应体预览。"
            )
        } else {
            List(tasks, selection: $selection) { task in
                PulseNetworkRowView(task: task)
                    .tag(PulseConsoleSelection.network(task.objectID))
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
    }
}

private struct PulseMessageRowView: View {
    let message: LoggerMessageEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(message.label.isEmpty ? "Remote Log" : message.label)
                        .font(.headline)
                        .lineLimit(1)

                    Text(message.text)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(message.formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    Text(message.logLevelTitle)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(message.logLevelColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(message.logLevelColor.opacity(0.12), in: Capsule())
                }
            }

            if !message.metadata.isEmpty {
                Text(message.metadataText)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct PulseNetworkRowView: View {
    let task: NetworkTaskEntity

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.httpMethod ?? "REQUEST")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Text(task.primaryURLText)
                        .font(.headline)
                        .lineLimit(1)

                    Text(task.secondaryNetworkSummary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(task.formattedTimestamp)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)

                    Text(task.statusDisplayText)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(task.statusAccentColor)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(task.statusAccentColor.opacity(0.12), in: Capsule())
                }
            }

            HStack(spacing: 12) {
                Label(task.responseBodySize.byteCountString, systemImage: "arrow.down.circle")
                Label(task.responseHeaderSummary, systemImage: "rectangle.compress.vertical")
            }
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
    }
}

private struct PulseEmptyStateView: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .center, spacing: 12) {
            Image(systemName: "waveform.path.ecg.rectangle")
                .font(.system(size: 28))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)

            Text(subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

#else
struct PulseConsoleHostView: View {
    let injector: PulseStoreInjector
    let category: LogCategory
    @Binding var selection: PulseConsoleSelection?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "shippingbox")
                .font(.title2)
                .foregroundStyle(.secondary)

            Text("Pulse Not Linked")
                .font(.headline)

            Text("当前 target 未链接 Pulse，无法构建自定义 Console。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Text("Store: \(injector.storeDescription)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
#endif
