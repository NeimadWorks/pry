# `PryHarness` — in-process Swift package

Linked into the app under test under `#if DEBUG`. Exposes a passive Unix
socket server, a state-introspection registry, a virtual clock for
deterministic time control, and a global animation toggle.

`PryHarness` is **passive** — it answers queries from outside. It never
drives the UI itself. All event injection happens out-of-process in
[`PryRunner`](PryRunner.md) / `pry-mcp`.

```swift
import PryHarness
```

---

## Install

```swift
.package(url: "https://github.com/neimad/pry", from: "0.1.0")

.target(name: "MyApp", dependencies: [
    .product(name: "PryHarness", package: "pry",
             condition: .when(configuration: .debug))
])
```

The `condition: .when(configuration: .debug)` ensures **zero linkage in
RELEASE builds** (Invariant 1 in [PROJECT-BIBLE §14](../../PROJECT-BIBLE.md#14-invariants)).

---

## Public surface

```swift
public enum PryHarness {
    public static let version: String

    /// Idempotent. Opens /tmp/pry-<bundleID>.sock; cleans stale sockets.
    public static func start(bundleID overrideID: String? = nil)

    public static func stop()
    public static func socketPath(for bundleID: String) -> String
}
```

### Bare-minimum adoption

```swift
@main
struct MyApp: App {
    init() {
        #if DEBUG
        PryHarness.start()
        #endif
    }
    var body: some Scene { /* ... */ }
}
```

---

## State introspection

### `PryInspectable`

```swift
@MainActor
public protocol PryInspectable: AnyObject {
    static var pryName: String { get }                        // default: type name
    func prySnapshot() -> [String: any Sendable]
}
```

VMs opt in by conforming and implementing `prySnapshot`. The dictionary keys
become the `path` strings used in `assert_state` and `pry_state`.

```swift
@MainActor
final class DocVM: ObservableObject, PryInspectable {
    @Published var documents: [Doc] = []
    @Published var isLoading = false
    @Published var selection: Doc.ID?

    func prySnapshot() -> [String: any Sendable] {
        [
            "documents.count": documents.count,
            "isLoading": isLoading,
            "selection.id": selection?.uuidString as Any,
        ]
    }
}
```

### `PryRegistry`

```swift
@MainActor
public final class PryRegistry {
    public static let shared: PryRegistry

    public func register<T: PryInspectable>(_ instance: T)
    public func unregister(name: String)
    public func snapshot(of name: String) -> [String: any Sendable]?
    public func registeredNames() -> [String]

    /// Force a diff & publish. Useful for VMs that don't conform to
    /// `PryStateBroadcaster` — call after a known mutation.
    public func notifyChange(_ name: String)
}
```

```swift
.task {
    #if DEBUG
    PryRegistry.shared.register(vm)
    #endif
}
```

### SwiftUI sugar: `View.pryRegister(_:)`

For SwiftUI view trees the manual `.task` / `.onDisappear` pair gets repetitive. Use the
`pryRegister` modifier — it registers on first appearance and unregisters when the view
leaves the hierarchy:

```swift
public extension View {
    /// Registers `instance` with `PryRegistry.shared` while this view is alive.
    /// No-op in RELEASE builds (the modifier compiles to identity).
    func pryRegister<T: PryInspectable>(_ instance: T) -> some View
}
```

```swift
struct DocumentListScreen: View {
    @StateObject private var vm = DocumentListVM()

    var body: some View {
        List(vm.documents) { /* ... */ }
            .pryRegister(vm)        // <-- one line, debug-only
    }
}
```

The modifier is a thin convenience over `register` / `unregister(name:)` and obeys the same
zero-RELEASE-linkage rule as the rest of `PryHarness`.

### `PryStateBroadcaster` (push notifications, ADR-008)

Optional conformance for VMs that want real-time push of state changes
without the runner having to poll. The harness watches for changes and
publishes to subscribed clients.

```swift
@MainActor
public protocol PryStateBroadcaster: PryInspectable {
    func prySubscribeStateChanges(_ notify: @escaping @MainActor () -> Void) -> any PryStateSubscription
}

public protocol PryStateSubscription {
    func cancel()
}
```

For Combine-backed VMs:

```swift
import Combine

extension DocVM: PryStateBroadcaster {
    func prySubscribeStateChanges(_ notify: @escaping @MainActor () -> Void) -> any PryStateSubscription {
        let cancellable = objectWillChange.sink { _ in Task { @MainActor in notify() } }
        return CombineSubscription(cancellable: cancellable)
    }
}

private struct CombineSubscription: PryStateSubscription {
    let cancellable: AnyCancellable
    func cancel() { cancellable.cancel() }
}
```

VMs that don't broadcast are still observable — the registry diffs on demand
when `notifyChange(_:)` is called manually, or when the runner polls via
`assert_state`/`wait_for`.

---

## Virtual clock (`PryClock`, ADR-007)

For determinism: replace `Date.now`, `Timer.scheduledTimer`,
`DispatchQueue.asyncAfter`, and `Task.sleep` with `PryClock` calls in
time-sensitive code paths. In production the clock delegates to the system;
in tests, `pry_clock_advance` / `Pry.advanceClock(by:)` fast-forwards it
without waiting real time.

```swift
public final class PryClock {
    public static let shared: PryClock

    public var now: Date              // current clock time
    public var isPaused: Bool

    /// Schedule work after `seconds` of clock time.
    @discardableResult
    public func after(_ seconds: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Token

    /// Async sleep that respects the virtual clock.
    public func sleep(_ seconds: TimeInterval) async

    public func cancel(_ token: Token)

    // Test-runner control (also reachable via `Pry.advanceClock(by:)`):
    @discardableResult public func advance(by seconds: TimeInterval) -> Int
    @discardableResult public func set(to date: Date, paused: Bool? = nil) -> Int
    public func pause()
    public func resume()
}
```

### Adoption pattern

Replace ad-hoc scheduling:

```swift
// Before:
DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.save() }

// After:
PryClock.shared.after(0.5) { [weak self] in
    Task { @MainActor in self?.save() }
}
```

```swift
// Before:
let now = Date()

// After:
let now = PryClock.shared.now
```

```swift
// Before:
try await Task.sleep(nanoseconds: 1_000_000_000)

// After:
await PryClock.shared.sleep(1.0)
```

Tests then control time:

```swift
let pry = try await Pry.launch(...)
try await pry.click(.id("trigger"))
try await pry.advanceClock(by: 5)   // fires anything scheduled within 5s, instantly
```

---

## Animations (`PryAnimations`, ADR-009)

```swift
@MainActor
public enum PryAnimations {
    public static var enabled: Bool { get }
    public static func setEnabled(_ on: Bool)
}
```

Disabling kills `CATransaction` actions and forces zero-duration
`NSAnimationContext`. Reachable via `Pry.setAnimations(enabled:)` or
spec frontmatter `animations: off`.

---

## Event bus (`PryEventBus`, ADR-008)

The internal pub/sub channel that backs `pry-mcp subscribe` and async
event handlers in specs. Producers (registry, harness) call `publish`;
consumers (the socket server, in turn the runner) subscribe.

```swift
public final class PryEventBus {
    public static let shared: PryEventBus
    public func subscribe(kinds: [PryWire.NotificationKind],
                          deliver: @escaping @Sendable (PryWire.NotificationParams) -> Void) -> String
    public func unsubscribe(_ id: String)
    public func publish(kind: PryWire.NotificationKind, data: PryWire.AnyCodable)
}
```

Most app authors don't touch this directly — `PryRegistry` publishes
`stateChanged` events automatically when VM snapshots diff.

---

## Logs (`PryLogTap`, ADR-006)

Best-effort `OSLogStore` reader — ~1 s flush latency. Suitable for the
"Relevant logs" verdict section, not race-sensitive assertions.

```swift
public enum PryLogTap {
    public struct Line: Sendable { /* date, level, subsystem, category, message */ }
    public static func readLines(since: Date?, subsystem: String?) -> [Line]
}
```

Reachable via `pry_logs` / `Pry.logs(...)`.

---

## What `PryHarness` does NOT do

- No event injection (clicks, keys, drag) — those happen in `PryRunner`.
- No spec parsing.
- No verdict formatting.
- No MCP protocol awareness.
- No state mutation. Read-only surface.

This is the **passive harness, active runner** split — see [ADR-002](../architecture/decisions/ADR-002-two-process-split.md)
and [Design principle 5](../design/principles.md#5-passive-harness-active-runner).

---

## Concurrency under Swift 6

- `PryHarness.start()` is callable from any context.
- `PryRegistry.shared` is `@MainActor`.
- `PryInspectable.prySnapshot()` is `@MainActor`-isolated.
- Snapshot values must be `Sendable` (enforced by `[String: any Sendable]`).
- The socket server runs on its own `DispatchQueue`; it hops to main when
  reading the registry via `DispatchQueue.main.sync { MainActor.assumeIsolated { ... } }`.
- `PryClock` is internally locked; safe to schedule from any actor.
