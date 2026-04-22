# `PryHarness` — in-process Swift package

The in-process half of Pry. You link this into your app under `#if DEBUG`. It starts a passive Unix-socket server that `pry-mcp` uses to read state, tail logs, and snapshot windows. It never drives the UI.

See [ADR-002](../architecture/decisions/ADR-002-two-process-split.md) for why the split exists, and [ADR-004](../architecture/decisions/ADR-004-state-introspection-protocol.md) for the introspection contract.

---

## Installation

```swift
// Package.swift
.package(url: "https://github.com/neimad/pry", from: "0.1.0")

.target(name: "MyApp", dependencies: [
    .product(
        name: "PryHarness",
        package: "pry",
        condition: .when(configuration: .debug)
    )
])
```

The `condition: .when(configuration: .debug)` ensures the dependency is not linked into RELEASE builds. This is Invariant 1 from [PROJECT-BIBLE §14](../../PROJECT-BIBLE.md#14-invariants).

---

## Public API

### `PryHarness.start()`

```swift
#if DEBUG
import PryHarness
#endif

@main
struct MyApp: App {
    init() {
        #if DEBUG
        PryHarness.start()
        #endif
    }
    var body: some Scene { ... }
}
```

- Idempotent: safe to call multiple times.
- No-op in RELEASE builds (the entire module is elided by `#if DEBUG`).
- Opens a Unix socket at `/tmp/pry-<bundleID>.sock`.
- Cleans up any orphaned socket from a previous crash before binding.

### `PryRegistry`

Central registry for `PryInspectable` ViewModels.

```swift
#if DEBUG
PryRegistry.shared.register(DocumentListVM.self) { vm in
    [
        "documents.count": vm.documents.count,
        "selection.id": vm.selection?.id.uuidString as Any,
        "isLoading": vm.isLoading,
    ]
}
#endif
```

Registration keys become the string paths used in spec `assert_state` / `pry_state`.

### `PryInspectable`

```swift
public protocol PryInspectable: AnyObject {
    static var pryName: String { get }
    func prySnapshot() -> [String: any Sendable]
}
```

Default `pryName` is the type name. Override only if you need a stable name across renames:

```swift
extension DocumentListVM: PryInspectable {
    static var pryName: String { "DocumentListVM" }
    func prySnapshot() -> [String: any Sendable] {
        [
            "documents.count": documents.count,
            "isLoading": isLoading,
        ]
    }
}
```

Two ways to wire it up — closure-based `register` (above) or protocol conformance. The closure form keeps Pry-specific code out of the ViewModel.

---

## What the harness responds to

These are JSON-RPC methods on the Unix socket. They are **not** public Swift API — `pry-mcp` calls them. Listed here for completeness.

| Method | Effect |
|---|---|
| `inspect_tree` | Walks in-process AX bridge + reports merged tree. (Fallback source; primary is out-of-process AX.) |
| `read_state` | Returns all registered `prySnapshot()` data, or a single key. |
| `read_logs` | Streams `OSLogStore` entries since a cursor. |
| `snapshot` | Renders the target window to PNG via `CGWindowListCreateImage`. |

---

## What the harness does NOT do

- No event injection. Clicks and keys come from `pry-mcp` via `CGEventPost`.
- No spec parsing. PryHarness has never heard of Markdown.
- No verdict formatting.
- No MCP protocol.
- No state mutation. It is a read-only surface for `pry-mcp`.

Invariant: [Design principle 5](../design/principles.md#5-passive-harness-active-runner).

---

## Concurrency

- `PryHarness.start()` is called from the main actor.
- The socket server runs on its own dispatch queue.
- `PryInspectable.prySnapshot()` is called on the main actor by default — safe to touch main-actor-isolated ViewModels.
- Returned values must be `Sendable` (enforced by `[String: any Sendable]`).

If your ViewModel is `@MainActor`-isolated (typical for SwiftUI), the default is correct. Non-main-actor ViewModels register with an explicit actor hop; see the closure-form registration.

---

## Threading invariants under Swift 6

- `PryRegistry.shared` is an `actor`.
- Snapshot closures you pass to `register` are `@Sendable`.
- Values you return from `prySnapshot()` must be `Sendable`. `String`, `Int`, `Bool`, `Double`, `Data`, and `[String: any Sendable]` / `[any Sendable]` nesting cover the 99% case.

If you hit a Sendable error, wrap the offending value in `String(describing:)` at the call site — the downstream consumers expect JSON-serializable values anyway.
