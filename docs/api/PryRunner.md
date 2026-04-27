# `PryRunner` — Swift library API

`PryRunner` is the runner half of Pry exposed as a normal Swift Package Manager library. Use it when you want to drive a Pry-instrumented app from Swift code without the MCP layer in the middle — XCTest targets, Swift Testing suites, custom CI tooling, scripts.

The MCP server (`pry-mcp`) is itself a thin wrapper around this library. Anything `pry-mcp` can do, you can do directly in Swift.

---

## Install

```swift
// Package.swift
dependencies: [
    .package(url: "https://github.com/neimad/pry", from: "0.1.0")
],
targets: [
    .testTarget(name: "MyAppTests", dependencies: [
        .product(name: "PryRunner", package: "pry")
    ])
]
```

You also need:
- `PryHarness` linked into the app under test (`#if DEBUG`). See [`PryHarness.md`](PryHarness.md).
- Accessibility permission on the parent process (Terminal, IDE, Xcode) that runs the tests.

---

## Two entry points

### `Pry.runSpec(...)` — spec-driven

Read a Markdown spec, get a `Verdict` back. The runner handles launch, step execution, failure context capture, attachment writing.

```swift
import PryRunner

let verdict = try await Pry.runSpec(atPath: "Tests/Flows/new-document.md")

if verdict.status != .passed {
    XCTFail(VerdictReporter.render(verdict))
}
```

Other forms:

```swift
let v = try await Pry.runSpec(markdown: inlineSpecText)
let vs = try await Pry.runSuite(at: "Tests/Flows", tag: "smoke")
```

Pass an `SpecRunner.Options` to override the verdicts directory or always-snapshot policy.

### `Pry.launch(...)` — programmatic

Drive the app step by step. You decide the order, the assertions, and what to do with failures.

```swift
let pry = try await Pry.launch(
    app: "fr.neimad.carnet",
    executablePath: "/path/to/Carnet.app/Contents/MacOS/Carnet"
)

try await pry.click(.id("new_game_button"))
try await pry.waitFor(window: "Carnet — Untitled")  // (helper not yet added; use AX assertions)

try await pry.click(.id("sq_e2"))
try await pry.click(.id("sq_e4"))

let ply: Int? = try await pry.state(of: "BoardVM", path: "ply")
XCTAssertEqual(ply, 1)

try await pry.drag(from: .id("piece_d2"), to: .id("sq_d4"))

let png = await pry.snapshotPNG()
try png?.write(to: URL(fileURLWithPath: "after-d4.png"))

await pry.terminate()
```

---

## Public API surface

### `actor Pry`

Top-level handle. One instance == one running target app.

| Method | What it does |
|---|---|
| `Pry.launch(app:executablePath:args:env:socketTimeout:)` | Launch + harness handshake. |
| `Pry.attach(to:)` | Attach to an already-running app. |
| `Pry.runSpec(_:)`, `runSpec(atPath:)`, `runSpec(markdown:)` | Execute a spec end-to-end. |
| `Pry.runSuite(at:tag:options:)` | Run every spec in a directory. |
| `pry.click(_:)`, `doubleClick`, `rightClick`, `type`, `key`, `drag(from:to:)`, `scroll(_:direction:amount:)` | Real CGEvent injection. |
| `pry.state(of:path:as:)` | Read one value as `T` (typed). |
| `pry.snapshot(of:)` | Read every key for a viewmodel. |
| `pry.tree(window:)` | Out-of-process AX tree as `AXNode`. |
| `pry.resolve(_:)` | Resolve a target to an AX element. |
| `pry.snapshotPNG()` | Capture front window as `Data`. |
| `pry.logs(since:subsystem:)` | OSLog read (best-effort, ~1s — ADR-006). |
| `pry.terminate()` | Send SIGTERM. |

### Spec types

`Spec`, `Step`, `Predicate`, `Target`, `StateExpectation`, `ScrollDirection`, `Duration` — all `public Sendable`. Build them programmatically or use `SpecParser.parse(source:)`.

### Verdict types

`Verdict`, `StepResult`, `FailureContext`, `VerdictReporter.render(_:)`. Frontmatter is stable YAML; consumers parse `status` first then descend.

---

## Targets

The same six forms as the spec format, in precedence order:

```swift
.id("new_doc_button")           // AXIdentifier exact
.roleLabel(role: "AXButton", label: "Save")
.label("Save")                  // AXTitle/AXDescription exact
.labelMatches(#"Doc.*"#)        // regex
.treePath("Window[0]/Group/Button[2]")  // positional
.point(x: 120, y: 340)          // last resort: absolute screen coords
```

Ambiguity (more than one match for a `id`/`roleLabel`/`label`/`labelMatches`) throws `ResolveError.ambiguous`. The resolver never silent-picks.

---

## Error contract

Public error types:

| Type | When |
|---|---|
| `PryError` | `noFrame`, `launchFailed`, `harnessHandshakeFailed`. |
| `ResolveError` | `accessibilityNotTrusted`, `windowNotFound`, `noMatch(_)`, `ambiguous(_, candidates:)`. |
| `AppDriver.DriverError` | `executableNotFound`, `bundleNotFound`, `launchFailed`, `harnessSocketTimeout`, `alreadyRunning`. |
| `HarnessClient.ClientError` | Socket errors + `rpcError(PryWire.RPCError)`. |
| `EventInjector.InjectError` | `eventCreateFailed`, `unknownKey`. |
| `SpecParseError` | `missingFrontmatter`, `frontmatterMalformed`, `unknownCommand`, `invalidArgument`. |

Each conforms to `CustomStringConvertible` for human-readable `description`.

---

## XCTest pattern

```swift
import XCTest
import PryRunner

final class CarnetFlows: XCTestCase {

    static var demoBinary: String!

    override class func setUp() {
        super.setUp()
        // Build once per test run; tests share the binary.
        demoBinary = ProcessInfo.processInfo.environment["CARNET_BINARY"]
            ?? "/path/to/.build/debug/Carnet"
    }

    func testOpening() async throws {
        let pry = try await Pry.launch(
            app: "fr.neimad.carnet",
            executablePath: Self.demoBinary
        )
        defer { Task { await pry.terminate() } }

        try await pry.click(.id("sq_e2"))
        try await pry.click(.id("sq_e4"))
        let ply: Int? = try await pry.state(of: "BoardVM", path: "ply")
        XCTAssertEqual(ply, 1)
    }

    func testWholeFlowSpec() async throws {
        let v = try await Pry.runSpec(atPath: "Tests/Flows/sicilian.md")
        XCTAssertEqual(v.status, .passed, VerdictReporter.render(v))
    }
}
```

CI: gate live tests on an `PRY_INTEGRATION=1` env var so plain `swift test` on machines without AX permission still passes the parser/render unit tests.

---

## Concurrency

`Pry` is an `actor` — calls serialize per-instance. Multiple `Pry` instances against different apps in parallel are fine. Multiple instances against the **same** app are not supported (the harness socket is per-bundle-ID).

Spec execution (`SpecRunner`) is also actor-isolated. Reentrancy is intentional only at well-defined points (the `wait_for` polling loop).

---

## What this is NOT

- Not a replacement for `XCUITest` if you live inside Xcode and that ergonomic suits you.
- Not a remote runner. The library runs locally, against a local app.
- Not real-time on logs — `pry.logs(...)` has ~1s latency by ADR-006. Use `assert_state` against an exposed VM property for race-sensitive checks.
