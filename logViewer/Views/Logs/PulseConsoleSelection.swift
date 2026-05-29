#if os(macOS) && canImport(Pulse)
import CoreData

enum PulseConsoleSelection: Hashable {
    case message(NSManagedObjectID)
    case network(NSManagedObjectID)
}
#else
enum PulseConsoleSelection: Hashable {
    case unavailable(String)
}
#endif
