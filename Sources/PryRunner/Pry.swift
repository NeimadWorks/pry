import Foundation
import CoreGraphics
import ApplicationServices
import PryWire
import PryHarness

/// Ergonomic Swift API for driving a Pry-instrumented app from any code
/// (tests, CLIs, custom runners) — without going through the MCP layer.
///
/// Two ways to use:
///
///     // Spec-driven: you write a Markdown spec, Pry runs it.
///     let verdict = try await Pry.runSpec(atPath: "flows/opening.md")
///
///     // Programmatic: launch, drive, assert step by step.
///     let pry = try await Pry.launch(
///         app: "fr.neimad.carnet",
///         executablePath: "/path/to/Carnet.app/Contents/MacOS/Carnet"
///     )
///     try await pry.click(.id("sq_e2"))
///     try await pry.click(.id("sq_e4"))
///     let ply: Int = try await pry.state(of: "BoardVM", path: "ply")
///     try await pry.terminate()
///
/// All methods that drive UI go through real `CGEvent` injection. State reads
/// hop to the harness over the Unix socket. Multiple concurrent `Pry`
/// instances against the same app are unsupported.
public actor Pry {

    public let bundleID: String
    public let pid: pid_t
    public let socketPath: String

    private let handle: AppDriver.Handle
    private let client: HarnessClient

    private init(handle: AppDriver.Handle, client: HarnessClient) {
        self.handle = handle
        self.client = client
        self.bundleID = handle.bundleID
        self.pid = handle.pid
        self.socketPath = handle.socketPath
    }

    // MARK: - Construction

    /// Launch the target app and wait for its PryHarness socket. If
    /// `executablePath` is supplied, launches the binary directly (useful for
    /// SwiftPM-built fixtures). Otherwise resolves the bundle via NSWorkspace.
    public static func launch(
        app bundleID: String,
        executablePath: String? = nil,
        args: [String] = [],
        env: [String: String] = [:],
        socketTimeout: TimeInterval = 5
    ) async throws -> Pry {
        let handle: AppDriver.Handle
        if let executablePath {
            handle = try AppDriver.launchByPath(
                executablePath: executablePath, bundleID: bundleID,
                args: args, env: env, socketTimeout: socketTimeout)
        } else {
            handle = try await AppDriver.launchByBundleID(
                bundleID, args: args, env: env, socketTimeout: socketTimeout)
        }

        let client = try HarnessClient(connectingTo: handle.socketPath)
        // Handshake with retry — accept() / listen() may race with first connect().
        let deadline = Date().addingTimeInterval(2)
        var lastErr: (any Error)?
        while Date() < deadline {
            do {
                _ = try await client.hello(client: "PryRunner", version: VerdictReporter.pryVersion)
                return Pry(handle: handle, client: client)
            } catch {
                lastErr = error
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        throw HarnessClient.ClientError.decodeFailed("hello handshake failed: \(lastErr.map { "\($0)" } ?? "timeout")")
    }

    /// Attach to an already-running app. The harness socket must be live.
    public static func attach(to bundleID: String) async throws -> Pry {
        let handle = try AppDriver.attach(bundleID: bundleID)
        let client = try HarnessClient(connectingTo: handle.socketPath)
        _ = try await client.hello(client: "PryRunner", version: VerdictReporter.pryVersion)
        return Pry(handle: handle, client: client)
    }

    /// Kill the target app cleanly.
    public func terminate() async {
        AppDriver.terminate(handle)
    }

    // MARK: - Control primitives

    public func click(_ target: Target, modifiers: [String] = []) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.click(at: CGPoint(x: f.midX, y: f.midY),
                                modifiers: EventInjector.parseModifiers(modifiers))
    }

    public func doubleClick(_ target: Target, modifiers: [String] = []) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.doubleClick(at: CGPoint(x: f.midX, y: f.midY),
                                      modifiers: EventInjector.parseModifiers(modifiers))
    }

    public func rightClick(_ target: Target, modifiers: [String] = []) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.rightClick(at: CGPoint(x: f.midX, y: f.midY),
                                     modifiers: EventInjector.parseModifiers(modifiers))
    }

    public func longPress(_ target: Target, dwellMs: Int = 800) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.longPress(at: CGPoint(x: f.midX, y: f.midY), dwellMs: dwellMs)
    }

    public func type(_ text: String, intervalMs: Int? = nil) async throws {
        try ElementResolver.requireTrust()
        if let intervalMs {
            try EventInjector.typeWithDelay(text: text, intervalMs: intervalMs)
        } else {
            try EventInjector.type(text: text)
        }
    }

    public func key(_ combo: String, repeat n: Int = 1) async throws {
        try ElementResolver.requireTrust()
        if n > 1 { try EventInjector.keyRepeat(combo: combo, count: n) }
        else { try EventInjector.key(combo: combo) }
    }

    /// Convenience helpers covering common keyboard shortcuts.
    public func copy() async throws { try await key("cmd+c") }
    public func paste() async throws { try await key("cmd+v") }
    public func cut() async throws { try await key("cmd+x") }
    public func selectAll() async throws { try await key("cmd+a") }
    public func undo() async throws { try await key("cmd+z") }

    /// Magnify (pinch approximation) at a target.
    public func magnify(_ target: Target, delta: Int) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.magnify(at: CGPoint(x: f.midX, y: f.midY), delta: Int32(delta))
    }

    public func drag(from: Target, to: Target, steps: Int = 12, modifiers: [String] = []) async throws {
        try ElementResolver.requireTrust()
        let rf = try ElementResolver.resolve(target: from, in: handle.pid)
        let rt = try ElementResolver.resolve(target: to, in: handle.pid)
        guard let ff = rf.frame, let tf = rt.frame else { throw PryError.noFrame(from) }
        let f = EventInjector.parseModifiers(modifiers)
        if !f.isEmpty {
            // Forward through the same flag-bearing CGEvent path used by SpecRunner.
            // Inline here to keep Pry.swift self-contained.
            let src = CGEventSource(stateID: .hidSystemState)
            let fromP = CGPoint(x: ff.midX, y: ff.midY)
            let toP = CGPoint(x: tf.midX, y: tf.midY)
            if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                               mouseCursorPosition: fromP, mouseButton: .left) {
                d.flags = f; d.post(tap: .cgSessionEventTap)
            }
            usleep(12_000)
            for i in 1...max(1, steps) {
                let t = Double(i) / Double(max(1, steps))
                let p = CGPoint(x: fromP.x + (toP.x - fromP.x) * t,
                                y: fromP.y + (toP.y - fromP.y) * t)
                if let m = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                                   mouseCursorPosition: p, mouseButton: .left) {
                    m.flags = f; m.post(tap: .cgSessionEventTap)
                }
                usleep(12_000)
            }
            if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                               mouseCursorPosition: toP, mouseButton: .left) {
                u.flags = f; u.post(tap: .cgSessionEventTap)
            }
        } else {
            try EventInjector.drag(
                from: CGPoint(x: ff.midX, y: ff.midY),
                to: CGPoint(x: tf.midX, y: tf.midY),
                steps: steps
            )
        }
    }

    public func scroll(_ target: Target, direction: ScrollDirection, amount: Int = 3) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        let p = CGPoint(x: f.midX, y: f.midY)
        let mag = Int32(amount)
        let (dx, dy): (Int32, Int32)
        switch direction {
        case .up: (dx, dy) = (0, mag)
        case .down: (dx, dy) = (0, -mag)
        case .left: (dx, dy) = (mag, 0)
        case .right: (dx, dy) = (-mag, 0)
        }
        try EventInjector.scroll(at: p, dx: dx, dy: dy)
    }

    // MARK: - Observation

    /// Read a single state value at `path`, decoded into `T`.
    /// Returns `nil` if the value is absent or has the wrong type.
    public func state<T: Sendable>(of viewmodel: String, path: String, as: T.Type = T.self) async throws -> T? {
        let result = try await client.readState(viewmodel: viewmodel, path: path)
        return result.value?.value as? T
    }

    /// Read every registered key for a viewmodel.
    public func snapshot(of viewmodel: String) async throws -> [String: any Sendable] {
        let result = try await client.readState(viewmodel: viewmodel, path: nil)
        guard let keys = result.keys else { return [:] }
        return keys.mapValues { $0.value }
    }

    /// Out-of-process AX tree.
    public func tree(window: WindowFilter? = nil) -> AXNode {
        AXTreeWalker.snapshot(pid: handle.pid, window: window)
    }

    /// Number of top-level windows owned by the target app.
    public func windowCount() -> Int {
        let app = AXUIElementCreateApplication(handle.pid)
        var attr: CFTypeRef?
        AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &attr)
        return (attr as? [AXUIElement])?.count ?? 0
    }

    /// Identifier of the currently focused element, if any.
    public func focusedIdentifier() -> String? {
        let app = AXUIElementCreateApplication(handle.pid)
        var attr: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedUIElementAttribute as CFString, &attr) == .success,
              let el = attr else { return nil }
        var idAttr: CFTypeRef?
        AXUIElementCopyAttributeValue(el as! AXUIElement, "AXIdentifier" as CFString, &idAttr)
        return idAttr as? String
    }

    /// Resolve a target — useful for asserting it's present without driving anything.
    public func resolve(_ target: Target) async throws -> Resolved {
        try ElementResolver.requireTrust()
        return try ElementResolver.resolve(target: target, in: handle.pid)
    }

    /// PNG of the target app's front window. Returns the data; caller chooses
    /// where (or whether) to write it.
    public func snapshotPNG() async -> Data? {
        await WindowCapture.capturePNG(pid: handle.pid)
    }

    /// Best-effort log read. ~1 s latency (ADR-006).
    public func logs(since: Date? = nil, subsystem: String? = nil) async throws -> [PryWire.LogLine] {
        let iso = since.map { ISO8601DateFormatter().string(from: $0) }
        return try await client.readLogs(since: iso, subsystem: subsystem).lines
    }

    // MARK: - Clock (ADR-007)

    /// Read the harness clock.
    public func clockNow() async throws -> Date {
        let r = try await client.clockGet()
        return ISO8601DateFormatter().date(from: r.iso8601) ?? Date()
    }

    /// Advance the virtual clock by `seconds`. Returns the number of scheduled
    /// callbacks that fired during the advance.
    @discardableResult
    public func advanceClock(by seconds: TimeInterval) async throws -> Int {
        let r = try await client.clockAdvance(seconds: seconds)
        return r.firedCallbacks
    }

    @discardableResult
    public func setClock(to date: Date, paused: Bool? = nil) async throws -> Int {
        let iso = ISO8601DateFormatter().string(from: date)
        let r = try await client.clockSet(iso8601: iso, paused: paused)
        return r.firedCallbacks
    }

    public func pauseClock() async throws { _ = try await client.clockSet(iso8601: ISO8601DateFormatter().string(from: try await clockNow()), paused: true) }
    public func resumeClock() async throws { _ = try await client.clockSet(iso8601: ISO8601DateFormatter().string(from: try await clockNow()), paused: false) }

    // MARK: - Animations (ADR-009)

    public func setAnimations(enabled: Bool) async throws {
        _ = try await client.setAnimations(enabled: enabled)
    }

    // MARK: - Pasteboard

    public func readPasteboard() async throws -> String? {
        try await client.readPasteboard().string
    }

    public func writePasteboard(_ string: String) async throws {
        _ = try await client.writePasteboard(string: string)
    }

    // MARK: - Spec runner

    /// Run a parsed spec against the currently-launched app.
    ///
    /// The runner expects the spec's `app` to match this `Pry`'s bundleID and
    /// will skip its own launch step if one is already managed externally.
    /// For the common case, prefer `Pry.runSpec(...)` static — it handles
    /// launch + run + cleanup as one call.
    public static func runSpec(_ spec: Spec, options: SpecRunner.Options = .init()) async -> Verdict {
        await SpecRunner(spec: spec, options: options).run()
    }

    public static func runSpec(atPath path: String, options: SpecRunner.Options = .init()) async throws -> Verdict {
        let url = URL(fileURLWithPath: path)
        let text = try String(contentsOf: url, encoding: .utf8)
        let spec = try SpecParser.parse(source: text, sourcePath: url.path)
        return await SpecRunner(spec: spec, options: options).run()
    }

    public static func runSpec(markdown: String, options: SpecRunner.Options = .init()) async throws -> Verdict {
        let spec = try SpecParser.parse(source: markdown, sourcePath: nil)
        return await SpecRunner(spec: spec, options: options).run()
    }

    /// Run every `.md` spec under `directory`, optionally filtered by tag.
    /// Sequential by default. Pass `parallel > 1` for concurrent execution
    /// across distinct apps. Specs targeting the same `app` are still serialized.
    public static func runSuite(at directory: String,
                                tag: String? = nil,
                                parallel: Int = 1,
                                retry: Int = 0,
                                options: SpecRunner.Options = .init()) async throws -> [Verdict] {
        let dir = URL(fileURLWithPath: directory)
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        var paths: [URL] = []
        while let u = enumerator?.nextObject() as? URL {
            if u.pathExtension.lowercased() == "md" { paths.append(u) }
        }
        paths.sort { $0.path < $1.path }

        var specs: [Spec] = []
        for url in paths {
            guard let text = try? String(contentsOf: url, encoding: .utf8),
                  let spec = try? SpecParser.parse(source: text, sourcePath: url.path) else {
                continue
            }
            if let tag, !spec.tags.contains(tag) { continue }
            specs.append(spec)
        }

        if parallel <= 1 {
            return await runSerial(specs, retry: retry, options: options)
        }
        return await runParallel(specs, maxConcurrent: parallel, retry: retry, options: options)
    }

    private static func runSerial(_ specs: [Spec], retry: Int, options: SpecRunner.Options) async -> [Verdict] {
        var verdicts: [Verdict] = []
        for spec in specs {
            verdicts.append(await runWithRetry(spec, retry: retry, options: options))
        }
        return verdicts
    }

    private static func runParallel(_ specs: [Spec], maxConcurrent: Int,
                                    retry: Int, options: SpecRunner.Options) async -> [Verdict] {
        // Group by app — specs hitting the same bundle ID must serialize so
        // they don't fight over /tmp/pry-<bundle>.sock.
        var byApp: [String: [Spec]] = [:]
        for s in specs { byApp[s.app, default: []].append(s) }

        return await withTaskGroup(of: [Verdict].self) { group in
            var added = 0
            let groups = byApp.values.sorted { $0[0].app < $1[0].app }
            for appGroup in groups {
                if added >= maxConcurrent {
                    // Wait until at least one finishes before adding more.
                    if let r = await group.next() {
                        // Already collected
                        _ = r
                        added -= 1
                    }
                }
                group.addTask {
                    var local: [Verdict] = []
                    for s in appGroup {
                        local.append(await runWithRetry(s, retry: retry, options: options))
                    }
                    return local
                }
                added += 1
            }
            var all: [Verdict] = []
            for await batch in group { all.append(contentsOf: batch) }
            // Preserve original spec order
            let order = Dictionary(uniqueKeysWithValues: specs.enumerated().map { ($1.id, $0) })
            all.sort { (order[$0.specID] ?? 0) < (order[$1.specID] ?? 0) }
            return all
        }
    }

    private static func runWithRetry(_ spec: Spec, retry: Int, options: SpecRunner.Options) async -> Verdict {
        var attempt = 0
        var verdict = await SpecRunner(spec: spec, options: options).run()
        while attempt < retry, verdict.status != .passed {
            attempt += 1
            verdict = await SpecRunner(spec: spec, options: options).run()
        }
        return verdict
    }
}

public enum PryError: Error, CustomStringConvertible {
    case noFrame(Target)
    case launchFailed(String)
    case harnessHandshakeFailed(String)

    public var description: String {
        switch self {
        case .noFrame(let t): return "target \(t) resolved but has no frame"
        case .launchFailed(let s): return "launch failed: \(s)"
        case .harnessHandshakeFailed(let s): return "harness handshake failed: \(s)"
        }
    }
}
