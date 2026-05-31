# Copilot instructions for `logViewer`

## Build, test, and lint

- Main scheme: `logViewer`
- List project metadata: `xcodebuild -list -project logViewer.xcodeproj`
- Build the macOS app: `xcodebuild -project logViewer.xcodeproj -scheme logViewer -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build`
- There is currently no committed XCTest target, so there is no full-suite or single-test command to run yet.
- There is currently no committed SwiftLint or SwiftFormat config in the repository.

## High-level architecture

- This is a single-target SwiftUI macOS app. `logViewerApp.swift` creates one `ConnectionManager` as the shared `@StateObject`, and `ContentView.swift` fans that state into a three-column `NavigationSplitView`: device list, live console, and detail inspector.
- The only external package currently pinned is Pulse (`logViewer.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`), and the app leans on Pulse/PulseUI/PulseProxy for storage and UI instead of maintaining a parallel in-house log database.
- `ConnectionManager.swift` is the runtime hub. On macOS it owns two inbound pipelines:
  - `MacLogReceiver.swift` browses `_logviewer-pipe._tcp` over Multipeer Connectivity and receives the app's custom `LogPacket` payloads from iOS senders.
  - `PulseRemoteLoggerServer.swift` listens on `_pulse._tcp` and speaks Pulse RemoteLogger's wire protocol so Pulse-enabled clients can stream richer log/network events directly.
- The custom Multipeer pipeline is defined in `Networking/LogPacketProtocol.swift` and `Networking/LogPacketCodec.swift`: packets are wrapped in a compact binary Property List envelope, then decoded into either message events or network summary events. `IOSLogSender.swift` is the iOS-side sender abstraction that emits those packets.
- Both pipelines normalize into the same app state: device presence/history is updated in `ConnectionManager`, while payloads are forwarded into `PulseStoreInjector.swift`.
- `PulseStoreInjector.swift` is the key translation boundary. It decodes custom packets with `LogPacketDecoder`, adapts Pulse RemoteLogger events, and writes everything into a temporary Pulse `LoggerStore`. The UI does not render packets directly; it renders Pulse/Core Data entities derived from that store.
- The console/detail UI is Pulse-backed on macOS:
  - `Views/Logs/PulseConsoleFormatting.swift` contains the active `PulseConsoleHostView` implementation for both message and network consoles.
  - `Views/Logs/PulseNetworkConsoleSupport.swift` owns the network query model (`PulseNetworkConsoleQuery`) plus the `NSFetchedResultsController`-based `PulseNetworkQueryController` that applies search/filter/group/sort state directly against the Pulse store.
  - `Views/Logs/PulseConsoleEntityFormatting.swift` and `Views/Detail/NetworkResponsePresentation.swift` are where raw Pulse entities get turned into display strings, cURL exports, syntax-highlighted JSON, image previews, and saveable response payloads.
  - `Views/Detail/LogDetailView.swift` reads `PulseConsoleSelection` and resolves the selected `NSManagedObjectID` back through `PulseStoreInjector` to show request/response/message details.
- `NetworkRequestBlocklist.swift` persists blocked hosts and URLs in `UserDefaults`. The blacklist is applied twice: during ingestion in `PulseStoreInjector` and again when querying/rendering network rows in the console.

## Key conventions

- Keep macOS/Pulse-only behavior behind `#if os(macOS) && canImport(Pulse)` gates and preserve the fallback placeholders for other builds. This repo uses compile-time splits instead of runtime availability branching.
- `Views/Logs/PulseConsoleHostView.swift` is intentionally just a stub comment; the real implementation lives in `Views/Logs/PulseConsoleFormatting.swift`.
- Cross-pane selection is always represented as `PulseConsoleSelection` carrying `NSManagedObjectID`s, not full model objects. Follow that pattern when wiring new console actions to the detail pane.
- `ConnectionManager` is `@MainActor`, and the networking layers publish upward via closures (`onPeerStateChange`, `onPacketReceived`, `onEventReceived`) instead of mutating view state directly.
- Device ordering and state are centralized in `ConnectionManager`: connected devices sort first, transfer rate is recomputed per packet/event, and connection history is appended there.
- When adding network filtering behavior, reuse `NetworkRequestBlocklist.normalizedHost` and `normalizedURL` so ingest-time filtering, persisted rules, and UI actions all match the same normalization rules.
- UI copy is intentionally mixed: major structure/tabs are English (`Devices`, `Messages`, `Network`, `Request`, `Response`), while much of the explanatory/status text is Chinese. Match the surrounding file instead of normalizing one language globally.
