import Combine
import Foundation

struct NetworkRequestBlocklistSnapshot: Equatable {
    static let empty = NetworkRequestBlocklistSnapshot(blockedHosts: [], blockedURLs: [])

    let blockedHosts: [String]
    let blockedURLs: [String]

    var isEmpty: Bool {
        blockedHosts.isEmpty && blockedURLs.isEmpty
    }

    var totalCount: Int {
        blockedHosts.count + blockedURLs.count
    }

    func matches(url: URL) -> Bool {
        matches(urlString: url.absoluteString, host: url.host)
    }

    func matches(urlString: String?, host: String?) -> Bool {
        if let normalizedURL = urlString.flatMap(NetworkRequestBlocklist.normalizedURL),
           blockedURLs.contains(normalizedURL) {
            return true
        }

        if let normalizedHost = host.flatMap(NetworkRequestBlocklist.normalizedHost),
           blockedHosts.contains(normalizedHost) {
            return true
        }

        return false
    }

    var exclusionPredicate: NSPredicate? {
        var predicates: [NSPredicate] = []

        if !blockedHosts.isEmpty {
            predicates.append(NSPredicate(format: "NOT (host IN %@)", blockedHosts))
        }

        if !blockedURLs.isEmpty {
            predicates.append(NSPredicate(format: "NOT (url IN %@)", blockedURLs))
        }

        switch predicates.count {
        case 0:
            return nil
        case 1:
            return predicates[0]
        default:
            return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        }
    }
}

enum NetworkRequestBlocklistMutationResult {
    case added
    case duplicate
    case invalid
}

@MainActor
final class NetworkRequestBlocklist: ObservableObject {
    @Published private(set) var blockedHosts: [String]
    @Published private(set) var blockedURLs: [String]

    private let defaults: UserDefaults
    private let defaultsKey: String

    init(
        defaults: UserDefaults = .standard,
        defaultsKey: String = "logviewer.network-request-blocklist"
    ) {
        self.defaults = defaults
        self.defaultsKey = defaultsKey

        if let data = defaults.data(forKey: defaultsKey),
           let persisted = try? JSONDecoder().decode(PersistedState.self, from: data) {
            blockedHosts = Self.sortedValues(persisted.blockedHosts)
            blockedURLs = Self.sortedValues(persisted.blockedURLs)
        } else {
            blockedHosts = []
            blockedURLs = []
        }
    }

    var snapshot: NetworkRequestBlocklistSnapshot {
        NetworkRequestBlocklistSnapshot(blockedHosts: blockedHosts, blockedURLs: blockedURLs)
    }

    func addHost(_ rawValue: String) -> NetworkRequestBlocklistMutationResult {
        guard let normalizedValue = Self.normalizedHost(rawValue) else {
            return .invalid
        }

        guard !blockedHosts.contains(normalizedValue) else {
            return .duplicate
        }

        blockedHosts = Self.sortedValues(blockedHosts + [normalizedValue])
        persist()
        return .added
    }

    func addURL(_ rawValue: String) -> NetworkRequestBlocklistMutationResult {
        guard let normalizedValue = Self.normalizedURL(rawValue) else {
            return .invalid
        }

        guard !blockedURLs.contains(normalizedValue) else {
            return .duplicate
        }

        blockedURLs = Self.sortedValues(blockedURLs + [normalizedValue])
        persist()
        return .added
    }

    func removeHost(_ value: String) {
        let previousCount = blockedHosts.count
        blockedHosts.removeAll { $0 == value }

        if blockedHosts.count != previousCount {
            persist()
        }
    }

    func removeURL(_ value: String) {
        let previousCount = blockedURLs.count
        blockedURLs.removeAll { $0 == value }

        if blockedURLs.count != previousCount {
            persist()
        }
    }

    func removeAll() {
        guard !snapshot.isEmpty else {
            return
        }

        blockedHosts = []
        blockedURLs = []
        persist()
    }

    static func normalizedHost(_ rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedValue.isEmpty else {
            return nil
        }

        if let parsedURL = URL(string: trimmedValue), let host = parsedURL.host {
            return host.lowercased()
        }

        var normalizedValue = trimmedValue.lowercased()

        if let schemeRange = normalizedValue.range(of: "://") {
            normalizedValue = String(normalizedValue[schemeRange.upperBound...])
        }

        if let slashIndex = normalizedValue.firstIndex(of: "/") {
            normalizedValue = String(normalizedValue[..<slashIndex])
        }

        if let colonIndex = normalizedValue.firstIndex(of: ":") {
            normalizedValue = String(normalizedValue[..<colonIndex])
        }

        normalizedValue = normalizedValue.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    static func normalizedURL(_ rawValue: String) -> String? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let parsedURL = URL(string: trimmedValue),
            var components = URLComponents(url: parsedURL, resolvingAgainstBaseURL: false),
            let scheme = components.scheme?.lowercased(),
            let host = components.host?.lowercased()
        else {
            return nil
        }

        components.scheme = scheme
        components.host = host
        components.fragment = nil

        if let normalizedURL = components.url {
            return normalizedURL.absoluteString
        }

        return components.string
    }

    private func persist() {
        let persistedState = PersistedState(blockedHosts: blockedHosts, blockedURLs: blockedURLs)

        if let data = try? JSONEncoder().encode(persistedState) {
            defaults.set(data, forKey: defaultsKey)
        }
    }

    private static func sortedValues(_ values: [String]) -> [String] {
        values.sorted { lhs, rhs in
            lhs.localizedCaseInsensitiveCompare(rhs) == .orderedAscending
        }
    }
}

private struct PersistedState: Codable {
    var blockedHosts: [String]
    var blockedURLs: [String]
}
