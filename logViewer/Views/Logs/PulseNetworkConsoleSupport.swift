import Foundation

#if os(macOS) && canImport(Pulse)
import Combine
import CoreData
import Pulse

enum PulseNetworkStatusFilter: String, CaseIterable, Hashable, Identifiable {
    case s2xx
    case s3xx
    case s4xx
    case s5xx

    var id: String { rawValue }

    var title: String {
        switch self {
        case .s2xx: return "2xx"
        case .s3xx: return "3xx"
        case .s4xx: return "4xx"
        case .s5xx: return "5xx"
        }
    }

    var predicate: NSPredicate {
        switch self {
        case .s2xx:
            return NSPredicate(format: "statusCode >= 200 AND statusCode < 300")
        case .s3xx:
            return NSPredicate(format: "statusCode >= 300 AND statusCode < 400")
        case .s4xx:
            return NSPredicate(format: "statusCode >= 400 AND statusCode < 500")
        case .s5xx:
            return NSPredicate(format: "statusCode >= 500 AND statusCode < 600")
        }
    }
}

enum PulseNetworkDurationFilter: String, CaseIterable, Identifiable {
    case any
    case underOneSecond
    case oneToFiveSeconds
    case overFiveSeconds

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any Duration"
        case .underOneSecond: return "< 1s"
        case .oneToFiveSeconds: return "1s - 5s"
        case .overFiveSeconds: return "> 5s"
        }
    }

    var predicate: NSPredicate? {
        switch self {
        case .any:
            return nil
        case .underOneSecond:
            return NSPredicate(format: "duration > 0 AND duration < 1")
        case .oneToFiveSeconds:
            return NSPredicate(format: "duration >= 1 AND duration <= 5")
        case .overFiveSeconds:
            return NSPredicate(format: "duration > 5")
        }
    }
}

enum PulseNetworkSizeFilter: String, CaseIterable, Identifiable {
    case any
    case underTenKilobytes
    case tenToHundredKilobytes
    case overHundredKilobytes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any Size"
        case .underTenKilobytes: return "< 10 KB"
        case .tenToHundredKilobytes: return "10 KB - 100 KB"
        case .overHundredKilobytes: return "> 100 KB"
        }
    }

    var predicate: NSPredicate? {
        switch self {
        case .any:
            return nil
        case .underTenKilobytes:
            return NSPredicate(format: "responseBodySize >= 0 AND responseBodySize < 10240")
        case .tenToHundredKilobytes:
            return NSPredicate(format: "responseBodySize >= 10240 AND responseBodySize <= 102400")
        case .overHundredKilobytes:
            return NSPredicate(format: "responseBodySize > 102400")
        }
    }
}

enum PulseNetworkErrorFilter: String, CaseIterable, Identifiable {
    case any
    case onlyErrors
    case withoutErrors

    var id: String { rawValue }

    var title: String {
        switch self {
        case .any: return "Any Error State"
        case .onlyErrors: return "Has Error"
        case .withoutErrors: return "No Error"
        }
    }

    var predicate: NSPredicate? {
        switch self {
        case .any:
            return nil
        case .onlyErrors:
            return NSPredicate(format: "requestState == 3 OR errorDomain != nil")
        case .withoutErrors:
            return NSPredicate(format: "requestState != 3 AND errorDomain == nil")
        }
    }
}

enum PulseNetworkGrouping: String, CaseIterable, Identifiable {
    case none
    case host
    case statusCode
    case method

    var id: String { rawValue }

    var title: String {
        switch self {
        case .none: return "No Grouping"
        case .host: return "Group by Host"
        case .statusCode: return "Group by Status"
        case .method: return "Group by Method"
        }
    }
}

enum PulseNetworkSortField: String, CaseIterable, Identifiable {
    case date
    case duration
    case size

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "Date"
        case .duration: return "Duration"
        case .size: return "Size"
        }
    }

    var key: String {
        switch self {
        case .date: return "createdAt"
        case .duration: return "duration"
        case .size: return "responseBodySize"
        }
    }
}

enum PulseNetworkSortDirection: String, CaseIterable, Identifiable {
    case descending
    case ascending

    var id: String { rawValue }

    var title: String {
        switch self {
        case .descending: return "Descending"
        case .ascending: return "Ascending"
        }
    }

    var isAscending: Bool {
        self == .ascending
    }
}

struct PulseNetworkConsoleQuery: Equatable {
    var searchText = ""
    var statusFilters: Set<PulseNetworkStatusFilter> = []
    var methodFilters: Set<String> = []
    var hostFilters: Set<String> = []
    var durationFilter: PulseNetworkDurationFilter = .any
    var sizeFilter: PulseNetworkSizeFilter = .any
    var errorFilter: PulseNetworkErrorFilter = .any
    var grouping: PulseNetworkGrouping = .none
    var sortField: PulseNetworkSortField = .date
    var sortDirection: PulseNetworkSortDirection = .descending

    var predicate: NSPredicate? {
        var predicates: [NSPredicate] = []

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSearch.isEmpty {
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: [
                    NSPredicate(format: "url CONTAINS[cd] %@", trimmedSearch),
                    NSPredicate(format: "host CONTAINS[cd] %@", trimmedSearch),
                    NSPredicate(format: "path CONTAINS[cd] %@", trimmedSearch),
                    NSPredicate(format: "httpMethod CONTAINS[cd] %@", trimmedSearch),
                    NSPredicate(format: "taskDescription CONTAINS[cd] %@", trimmedSearch),
                    NSPredicate(format: "errorDomain CONTAINS[cd] %@", trimmedSearch)
                ])
            )
        }

        if !statusFilters.isEmpty {
            predicates.append(
                NSCompoundPredicate(orPredicateWithSubpredicates: statusFilters.map(\.predicate))
            )
        }

        if !methodFilters.isEmpty {
            predicates.append(NSPredicate(format: "httpMethod IN %@", Array(methodFilters).sorted()))
        }

        if !hostFilters.isEmpty {
            predicates.append(NSPredicate(format: "host IN %@", Array(hostFilters).sorted()))
        }

        if let durationPredicate = durationFilter.predicate {
            predicates.append(durationPredicate)
        }

        if let sizePredicate = sizeFilter.predicate {
            predicates.append(sizePredicate)
        }

        if let errorPredicate = errorFilter.predicate {
            predicates.append(errorPredicate)
        }

        guard !predicates.isEmpty else {
            return nil
        }

        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    var sortDescriptors: [NSSortDescriptor] {
        var descriptors = [NSSortDescriptor(key: sortField.key, ascending: sortDirection.isAscending)]

        if sortField != .date {
            descriptors.append(NSSortDescriptor(key: PulseNetworkSortField.date.key, ascending: false))
        }

        return descriptors
    }
}

struct PulseNetworkGroupSection: Identifiable {
    let id: String
    let title: String
    var tasks: [NetworkTaskEntity]
}

@MainActor
final class PulseNetworkQueryController: NSObject, ObservableObject, NSFetchedResultsControllerDelegate {
    @Published private(set) var tasks: [NetworkTaskEntity] = []
    @Published private(set) var availableHosts: [String] = []
    @Published private(set) var availableMethods: [String] = []

    private let context: NSManagedObjectContext
    private var fetchedResultsController: NSFetchedResultsController<NetworkTaskEntity>?
    private var currentQuery = PulseNetworkConsoleQuery()

    init(context: NSManagedObjectContext) {
        self.context = context
        super.init()
        apply(query: currentQuery)
        refreshFacets()
    }

    func apply(query: PulseNetworkConsoleQuery) {
        currentQuery = query

        let request = NSFetchRequest<NetworkTaskEntity>(entityName: "NetworkTaskEntity")
        request.predicate = query.predicate
        request.sortDescriptors = query.sortDescriptors
        request.fetchBatchSize = 200
        request.returnsObjectsAsFaults = false

        let controller = NSFetchedResultsController(
            fetchRequest: request,
            managedObjectContext: context,
            sectionNameKeyPath: nil,
            cacheName: nil
        )
        controller.delegate = self
        fetchedResultsController = controller

        do {
            try controller.performFetch()
            tasks = controller.fetchedObjects ?? []
        } catch {
            tasks = []
            print("[logViewer][NetworkConsole] fetch failed: \(error.localizedDescription)")
        }

        refreshFacets()
    }

    func controllerDidChangeContent(_ controller: NSFetchedResultsController<any NSFetchRequestResult>) {
        tasks = fetchedResultsController?.fetchedObjects ?? []
        refreshFacets()
    }

    func makeSections(grouping: PulseNetworkGrouping) -> [PulseNetworkGroupSection] {
        guard grouping != .none else {
            return []
        }

        var orderedSections: [PulseNetworkGroupSection] = []
        var sectionLookup: [String: Int] = [:]

        for task in tasks {
            let title = task.groupTitle(for: grouping)
            let id = "\(grouping.rawValue)::\(title)"

            if let index = sectionLookup[id] {
                orderedSections[index].tasks.append(task)
            } else {
                sectionLookup[id] = orderedSections.count
                orderedSections.append(PulseNetworkGroupSection(id: id, title: title, tasks: [task]))
            }
        }

        return orderedSections
    }

    private func refreshFacets() {
        availableHosts = fetchDistinctValues(for: "host")
        availableMethods = fetchDistinctValues(for: "httpMethod")
    }

    private func fetchDistinctValues(for key: String) -> [String] {
        let request = NSFetchRequest<NSDictionary>(entityName: "NetworkTaskEntity")
        request.resultType = .dictionaryResultType
        request.returnsDistinctResults = true
        request.propertiesToFetch = [key]
        request.propertiesToGroupBy = [key]
        request.predicate = NSPredicate(format: "%K != nil AND %K != ''", key, key)

        do {
            return try context.fetch(request)
                .compactMap { $0[key] as? String }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        } catch {
            print("[logViewer][NetworkConsole] facet fetch failed: \(error.localizedDescription)")
            return []
        }
    }
}

extension NetworkTaskEntity {
    func groupTitle(for grouping: PulseNetworkGrouping) -> String {
        switch grouping {
        case .none:
            return "Ungrouped"
        case .host:
            return host.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown Host"
        case .statusCode:
            return statusGroupTitle
        case .method:
            return httpMethod.flatMap { $0.isEmpty ? nil : $0 } ?? "Unknown Method"
        }
    }

    var statusGroupTitle: String {
        switch statusCode {
        case 200..<300:
            return "2xx Success"
        case 300..<400:
            return "3xx Redirection"
        case 400..<500:
            return "4xx Client Error"
        case 500..<600:
            return "5xx Server Error"
        default:
            return state == .failure ? "Failed without Status" : "Unknown Status"
        }
    }

    var methodDisplayText: String {
        httpMethod ?? "—"
    }

    var hostDisplayText: String {
        host ?? "—"
    }

    var sizeDisplayText: String {
        guard responseBodySize > 0 else {
            return "0 B"
        }
        return ByteCountFormatter.string(fromByteCount: responseBodySize, countStyle: .binary)
    }

    var errorDisplayText: String {
        if state == .failure || errorDomain != nil {
            if let errorDebugDescription, !errorDebugDescription.isEmpty {
                return errorDebugDescription
            }
            if let errorDomain, !errorDomain.isEmpty {
                return "\(errorDomain) (\(errorCode))"
            }
            return "Request failed"
        }
        return "—"
    }
}
#endif
