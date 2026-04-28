# `PryRunner` — Swift library API

Public Swift package. Use it from any Swift code (XCTest, Swift Testing,
custom CLIs, scripts) without going through MCP. The `pry-mcp` server is
itself a thin wrapper around `PryRunner` — anything `pry-mcp` exposes, you
can do directly via this library.

```swift
import PryRunner
```

---

## Install

```swift
.package(url: "https://github.com/neimad/pry", from: "0.1.0")

.testTarget(name: "MyAppTests", dependencies: [
    .product(name: "PryRunner", package: "pry")
])
```

You also need to link [`PryHarness`](PryHarness.md) into the app under test
(`#if DEBUG`), and grant Accessibility to the parent process.

---

## Two entry points

### `Pry.runSpec(...)` — spec-driven

```swift
let v = try await Pry.runSpec(atPath: "Tests/Flows/foo.md")
if v.status != .passed {
    XCTFail(VerdictReporter.render(v))
}
```

Variants:

```swift
try await Pry.runSpec(markdown: inlineSource)
try await Pry.runSuite(at: "Tests/Flows", tag: "smoke",
                        parallel: 4, retry: 1)
```

Pass `SpecRunner.Options` to override the verdicts directory or screenshot
policy.

### `Pry.launch(...)` — programmatic

```swift
let pry = try await Pry.launch(
    app: "fr.neimad.carnet",
    executablePath: "/path/to/Carnet"
)
defer { Task { await pry.terminate() } }

try await pry.click(.id("sq_e2"))
try await pry.click(.id("sq_e4"))
let ply: Int? = try await pry.state(of: "BoardVM", path: "ply")
XCTAssertEqual(ply, 1)
```

Multiple `Pry` instances against different apps run in parallel.
Multiple instances against the *same* app are not supported (the harness
socket is per-bundle-ID).

---

## `Pry` actor — full API

### Construction

```swift
public static func launch(
    app bundleID: String,
    executablePath: String? = nil,
    args: [String] = [],
    env: [String: String] = [:],
    socketTimeout: TimeInterval = 5
) async throws -> Pry

public static func attach(to bundleID: String) async throws -> Pry
public func terminate() async
```

### Control primitives

```swift
public func click(_ target: Target, modifiers: [String] = []) async throws
public func doubleClick(_ target: Target, modifiers: [String] = []) async throws
public func rightClick(_ target: Target, modifiers: [String] = []) async throws
public func longPress(_ target: Target, dwellMs: Int = 800) async throws

public func type(_ text: String, intervalMs: Int? = nil) async throws
public func key(_ combo: String, repeat n: Int = 1) async throws

public func drag(from: Target, to: Target, steps: Int = 12, modifiers: [String] = []) async throws
public func scroll(_ target: Target, direction: ScrollDirection, amount: Int = 3) async throws
public func magnify(_ target: Target, delta: Int) async throws

public func copy() async throws
public func paste() async throws
public func cut() async throws
public func selectAll() async throws
public func undo() async throws
```

`modifiers` strings: `cmd`, `shift`, `opt` / `option` / `alt`, `ctrl`,
`fn` / `function`. Symbol forms (`⌘`, `⇧`, `⌥`, `⌃`) are accepted.

### Observation

```swift
public func state<T: Sendable>(of viewmodel: String, path: String,
                                as: T.Type = T.self) async throws -> T?
public func snapshot(of viewmodel: String) async throws -> [String: any Sendable]
public func tree(window: WindowFilter? = nil) -> AXNode
public func resolve(_ target: Target) async throws -> Resolved
public func snapshotPNG() async -> Data?
public func logs(since: Date? = nil, subsystem: String? = nil) async throws -> [PryWire.LogLine]
public func windowCount() -> Int
public func focusedIdentifier() -> String?
```

### Time control (ADR-007)

```swift
public func clockNow() async throws -> Date
public func advanceClock(by seconds: TimeInterval) async throws -> Int
public func setClock(to date: Date, paused: Bool? = nil) async throws -> Int
public func pauseClock() async throws
public func resumeClock() async throws
```

The returned `Int` is the number of `PryClock`-scheduled callbacks that
fired during the operation.

### Animations (ADR-009)

```swift
public func setAnimations(enabled: Bool) async throws
```

### Pasteboard

```swift
public func readPasteboard() async throws -> String?
public func writePasteboard(_ string: String) async throws
```

### File panels (NSOpenPanel / NSSavePanel)

```swift
public func openFile(_ path: String) async throws       // drive open panel
public func saveFile(_ path: String) async throws       // drive save panel
public func acceptPanel(button: String? = nil) async throws
public func cancelPanel() async throws
```

Use after triggering the panel (via `select_menu`, button click, or app
action). The helpers wait up to 2s for the panel to surface in the AX tree.
Works for both sheet-attached and modal-window panel forms.

### Spec running (statics)

```swift
public static func runSpec(_ spec: Spec, options: SpecRunner.Options = .init()) async -> Verdict
public static func runSpec(atPath path: String, options: SpecRunner.Options = .init()) async throws -> Verdict
public static func runSpec(markdown: String, options: SpecRunner.Options = .init()) async throws -> Verdict

public static func runSuite(at directory: String,
                            tag: String? = nil,
                            parallel: Int = 1,
                            retry: Int = 0,
                            options: SpecRunner.Options = .init()) async throws -> [Verdict]
```

`runSuite` groups specs by `app`; specs targeting the same bundle ID
serialize, distinct apps run concurrently up to `parallel`. `retry` retries
each non-passed spec up to N times.

---

## Spec types

```swift
public struct Spec: Sendable { /* id, app, steps, setupSteps, teardownSteps,
                                  flows, handlers, withFS, withDefaults,
                                  variables, animationsEnabled,
                                  screenshotsPolicy, ... */ }

public enum Step: Sendable { /* every grammar command */ }
public enum Predicate: Sendable {
    case contains(TargetRef)
    case notContains(TargetRef)
    case countOf(TargetRef, op: NumOp)         // numeric op replaces fixed equals
    case visible(TargetRef)
    case enabled(TargetRef)
    case focused(TargetRef)
    case state(viewmodel: String, path: String, expect: StateExpectation)
    case allOf([Predicate])
    case anyOf([Predicate])
    case not(Predicate)
    case window(title: String?, titleMatches: String?)
    case panelOpen(titleMatches: String?)      // matches AXSheet OR modal AXWindow
    case sheetOpen(titleMatches: String?)      // AXSheet only — distinct from panelOpen
    case stableFor(Predicate, seconds: Double) // anti-flicker: must hold continuously
}

public indirect enum TargetRef: Sendable {
    case id(String)
    case roleLabel(role: String, label: String)
    case label(String)
    case labelMatches(String)
    case treePath(String)
    case point(x: Double, y: Double)
    /// `nth(base, index, expectedTotal)` — `expectedTotal` makes the selection
    /// self-checking; the resolver fails if the match count diverges.
    case nth(base: TargetRef, index: Int, expectedTotal: Int?)
}

public enum StateExpectation: Sendable {
    case equals(YAMLValue)
    case notEquals(YAMLValue)
    case matches(String)                       // auto-coerces Int/Double to string
    case notMatches(String)
    case anyOf([YAMLValue])
    case gt(Double)
    case gte(Double)
    case lt(Double)
    case lte(Double)
    case between(low: Double, high: Double)
}

public enum NumOp: Sendable, Equatable {
    case eq(Int), gt(Int), gte(Int), lt(Int), lte(Int), between(Int, Int)
    public func matches(_ n: Int) -> Bool
}

public enum ScrollDirection: String, Sendable { case up, down, left, right }
public struct Duration: Sendable { /* seconds */ }

public struct FilesystemFixture: Sendable { /* basePath, entries */ }
public enum ScreenshotsPolicy: String, Sendable { case never, onFailure, everyStep, always }

public enum SpecParser {
    public static func parse(source: String, sourcePath: String? = nil) throws -> Spec
}

public enum SpecParseError: Error { /* missingFrontmatter, unknownCommand(line), ... */ }

/// Project-wide config loaded from `.pry/config.yaml`. Walks up from a spec
/// file (8 ancestor levels) looking for the file. Lets specs omit
/// `executable_path:` from their frontmatter — particularly useful for
/// SwiftPM-built apps whose path varies per machine.
public struct PryConfig: Sendable {
    public struct AppConfig: Sendable {
        public var executablePath: String?
        public var autoBuild: Bool        // run `swift build` before launch
    }
    public var configFileURL: URL?
    public var apps: [String: AppConfig]

    /// Highest-precedence path resolution: env var
    /// `PRY_EXEC_<UPPERCASED_BUNDLE_ID>` (`.` and `-` → `_`), then config
    /// file, then nil.
    public func resolveExecutablePath(for bundleID: String) -> String?

    /// `auto_build: true` lookup. Driven from `apps[<bundle-id>].auto_build`
    /// in the config file. False by default.
    public func autoBuild(for bundleID: String) -> Bool

    /// Run `swift build` (no args) from the config file's directory.
    /// Throws on non-zero exit with the captured stderr in the message.
    public func runSwiftBuild() throws

    public static func discover(from start: URL) -> PryConfig?
    public static func load(from url: URL) throws -> PryConfig
}
```

---

## Verdict types

```swift
public struct Verdict: Sendable {
    public enum Status: String, Sendable { case passed, failed, errored, timedOut }
    public var specPath: String?
    public var specID: String
    public var app: String
    public var status: Status
    public var duration: TimeInterval
    public var stepsTotal: Int
    public var stepsPassed: Int
    public var failedAtStep: Int?
    public var startedAt: Date
    public var finishedAt: Date
    public var stepResults: [StepResult]
    public var failure: FailureContext?
    public var errorKind: String?
    public var errorMessage: String?
    public var attachmentsDir: URL?
}

public enum VerdictReporter {
    public static let pryVersion: String
    public static func render(_ verdict: Verdict) -> String  // canonical Markdown
}

public enum VerdictExporters {
    public static func junit(_ verdicts: [Verdict]) -> String
    public static func tap(_ verdicts: [Verdict]) -> String
    public static func markdownSummary(_ verdicts: [Verdict]) -> String
}
```

---

## Lower-level building blocks

For when the `Pry` actor doesn't fit (e.g. fully custom orchestration):

```swift
public enum AppDriver {
    public static func launchByPath(...) throws -> Handle
    public static func launchByBundleID(_:...) async throws -> Handle
    public static func attach(bundleID: String) throws -> Handle
    public static func terminate(_ handle: Handle, timeout: TimeInterval = 3)
    public static func waitForSocket(path: String, timeout: TimeInterval) throws
}

public actor HarnessClient {
    public init(connectingTo path: String) throws
    public func hello(client: String, version: String) async throws -> PryWire.HelloResult
    public func readState(viewmodel: String, path: String?) async throws -> PryWire.ReadStateResult
    public func readLogs(since: String?, subsystem: String?) async throws -> PryWire.ReadLogsResult
    public func clockGet() async throws -> PryWire.ClockGetResult
    public func clockSet(iso8601: String, paused: Bool?) async throws -> PryWire.ClockSetResult
    public func clockAdvance(seconds: Double) async throws -> PryWire.ClockSetResult
    public func setAnimations(enabled: Bool) async throws -> PryWire.SetAnimationsResult
    public func subscribe(kinds: [PryWire.NotificationKind]) async throws -> PryWire.SubscribeResult
    public func unsubscribe(_ id: String) async throws -> PryWire.UnsubscribeResult
    public func readPasteboard() async throws -> PryWire.ReadPasteboardResult
    public func writePasteboard(string: String) async throws -> PryWire.WritePasteboardResult
}

public enum ElementResolver {
    public static func requireTrust() throws
    public static func resolve(target: Target, in pid: pid_t) throws -> Resolved
}

public enum EventInjector {
    public static func click(at: CGPoint, modifiers: CGEventFlags = []) throws
    public static func drag(from: CGPoint, to: CGPoint, steps: Int = 12,
                            dwellMicros: useconds_t = 12_000) throws
    public static func scroll(at: CGPoint, dx: Int32, dy: Int32) throws
    public static func magnify(at: CGPoint, delta: Int32) throws
    public static func longPress(at: CGPoint, dwellMs: Int = 800) throws
    public static func hoverDwell(at: CGPoint, dwellMs: Int = 800) throws
    public static func type(text: String) throws
    public static func typeWithDelay(text: String, intervalMs: Int = 30) throws
    public static func key(combo: String) throws
    public static func keyRepeat(combo: String, count: Int) throws
    public static func parseModifiers(_ tokens: [String]) -> CGEventFlags
}

public enum AXTreeWalker {
    public static func snapshot(pid: pid_t, window: WindowFilter? = nil) -> AXNode
    public static func resolveWindow(pid: pid_t, filter: WindowFilter?) -> AXUIElement?
    public static func renderYAML(_ node: AXNode, indent: Int = 0) -> String
    public static func truncated(_ tree: AXNode, maxDepth: Int = 4, maxChildren: Int = 6) -> AXNode
}

public enum WindowCapture {
    public static func capturePNG(pid: pid_t) async -> Data?
}

public enum FilesystemFixtures {
    public static func install(_ fixture: FilesystemFixture, specID: String) throws -> URL
    public static func cleanup(_ baseURL: URL)
}
public enum DefaultsFixtures {
    public static func install(bundleID: String, values: [String: YAMLValue]) -> Snapshot
    public static func restore(_ snapshot: Snapshot)
}

public enum ImageDiff {
    public static func diff(reference: Data, observed: Data,
                            perChannelTolerance: Int = 4) -> Result
}

public enum AccessibilityAudit {
    public static func audit(_ tree: AXNode) -> [Issue]
    public static func render(_ issues: [Issue]) -> String
}
```

---

## Errors

| Type | When |
|---|---|
| `PryError` | `noFrame(Target)`, `launchFailed`, `harnessHandshakeFailed` |
| `ResolveError` | `accessibilityNotTrusted`, `windowNotFound`, `noMatch(Target)`, `ambiguous(Target, candidates: [String])` |
| `AppDriver.DriverError` | `executableNotFound`, `bundleNotFound`, `launchFailed`, `harnessSocketTimeout`, `alreadyRunning` |
| `HarnessClient.ClientError` | socket errors + `rpcError(PryWire.RPCError)` |
| `EventInjector.InjectError` | `eventCreateFailed`, `unknownKey` |
| `SpecParseError` | parser errors with line numbers |

All conform to `CustomStringConvertible`.

---

## Concurrency

- `Pry` is an `actor` — calls serialize per instance.
- `SpecRunner` is also actor-isolated; reentrancy is intentional only at
  `wait_for` polling and inside async handlers.
- Handler bodies execute serially per handler; multiple handlers can fire
  concurrently.
- `PryClock`, `PryRegistry`, and `PryAnimations` (in `PryHarness`) are
  thread-safe across actors.

---

## XCTest pattern

```swift
import XCTest
import PryRunner

final class CarnetFlows: XCTestCase {
    static let demoBinary = ProcessInfo.processInfo.environment["CARNET_BINARY"]
        ?? "/path/to/.build/debug/Carnet"

    override func setUpWithError() throws {
        try XCTSkipUnless(FileManager.default.isExecutableFile(atPath: Self.demoBinary),
                          "Carnet binary not built")
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

    func testSicilianSpec() async throws {
        let v = try await Pry.runSpec(atPath: "Tests/Flows/sicilian.md")
        XCTAssertEqual(v.status, .passed, VerdictReporter.render(v))
    }
}
```

CI: gate live tests on `PRY_INTEGRATION=1` so plain `swift test` on machines
without Accessibility permission still passes the parser/render unit tests.
