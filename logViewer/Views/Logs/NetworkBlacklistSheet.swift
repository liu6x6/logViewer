import SwiftUI

struct NetworkBlacklistSheet: View {
    @ObservedObject var blocklist: NetworkRequestBlocklist
    @Environment(\.dismiss) private var dismiss

    @State private var hostInput = ""
    @State private var urlInput = ""
    @State private var hostFeedback: FeedbackMessage?
    @State private var urlFeedback: FeedbackMessage?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            HStack(alignment: .top, spacing: 16) {
                inputCard(
                    title: "Block Host",
                    subtitle: "例如 api.example.com。命中后，该 host 的请求会从列表中隐藏，并阻止后续写入。",
                    text: $hostInput,
                    buttonTitle: "Add Host",
                    systemImage: "network",
                    feedback: hostFeedback,
                    action: submitHost
                )

                inputCard(
                    title: "Block URL",
                    subtitle: "例如 https://api.example.com/v1/ping。仅匹配完整 URL。",
                    text: $urlInput,
                    buttonTitle: "Add URL",
                    systemImage: "link",
                    feedback: urlFeedback,
                    action: submitURL
                )
            }

            HStack(spacing: 10) {
                summaryChip(title: "Hosts", value: "\(blocklist.blockedHosts.count)")
                summaryChip(title: "URLs", value: "\(blocklist.blockedURLs.count)")
            }

            HStack(alignment: .top, spacing: 16) {
                ruleList(
                    title: "Blocked Hosts",
                    systemImage: "shield.lefthalf.filled",
                    rules: blocklist.blockedHosts,
                    emptyText: "还没有被屏蔽的 host。",
                    remove: blocklist.removeHost
                )

                ruleList(
                    title: "Blocked URLs",
                    systemImage: "shield",
                    rules: blocklist.blockedURLs,
                    emptyText: "还没有被屏蔽的 URL。",
                    remove: blocklist.removeURL
                )
            }
        }
        .padding(20)
        .frame(minWidth: 860, minHeight: 520, alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Network Blacklist")
                    .font(.title3.weight(.semibold))

                Text("添加 host 或完整 URL 后，匹配的网络请求会在当前列表中隐藏，并在后续接入时直接跳过。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            HStack(spacing: 10) {
                if !blocklist.snapshot.isEmpty {
                    Button("Clear Blacklist", role: .destructive) {
                        blocklist.removeAll()
                        hostFeedback = nil
                        urlFeedback = nil
                    }
                    .buttonStyle(.bordered)
                }

                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func inputCard(
        title: String,
        subtitle: String,
        text: Binding<String>,
        buttonTitle: String,
        systemImage: String,
        feedback: FeedbackMessage?,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                TextField(title, text: text)
                    .textFieldStyle(.roundedBorder)

                Button(buttonTitle, action: action)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }

            if let feedback {
                Text(feedback.message)
                    .font(.caption)
                    .foregroundStyle(feedback.color)
            } else {
                Spacer()
                    .frame(height: 16)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func ruleList(
        title: String,
        systemImage: String,
        rules: [String],
        emptyText: String,
        remove: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(title, systemImage: systemImage)
                    .font(.headline)

                Spacer()

                Text("\(rules.count)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.thinMaterial, in: Capsule())
            }

            if rules.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyText)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .topLeading)
                .padding(16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                List {
                    ForEach(rules, id: \.self) { rule in
                        HStack(spacing: 12) {
                            Text(rule)
                                .font(.subheadline.monospaced())
                                .textSelection(.enabled)

                            Spacer(minLength: 12)

                            Button(role: .destructive) {
                                remove(rule)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
                .listStyle(.inset(alternatesRowBackgrounds: true))
                .frame(maxWidth: .infinity, minHeight: 220)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func summaryChip(title: String, value: String) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .fontWeight(.semibold)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.quaternary, in: Capsule())
    }

    private func submitHost() {
        switch blocklist.addHost(hostInput) {
        case .added:
            hostInput = ""
            hostFeedback = FeedbackMessage(message: "Host 已加入黑名单。", color: .green)
        case .duplicate:
            hostFeedback = FeedbackMessage(message: "这个 host 已经存在。", color: .orange)
        case .invalid:
            hostFeedback = FeedbackMessage(message: "请输入有效的 host，例如 api.example.com。", color: .red)
        }
    }

    private func submitURL() {
        switch blocklist.addURL(urlInput) {
        case .added:
            urlInput = ""
            urlFeedback = FeedbackMessage(message: "URL 已加入黑名单。", color: .green)
        case .duplicate:
            urlFeedback = FeedbackMessage(message: "这个 URL 已经存在。", color: .orange)
        case .invalid:
            urlFeedback = FeedbackMessage(message: "请输入完整 URL，例如 https://api.example.com/v1/ping。", color: .red)
        }
    }
}

private struct FeedbackMessage {
    let message: String
    let color: Color
}
