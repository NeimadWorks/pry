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

    public func click(_ target: Target) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.click(at: CGPoint(x: f.midX, y: f.midY))
    }

    public func doubleClick(_ target: Target) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.doubleClick(at: CGPoint(x: f.midX, y: f.midY))
    }

    public func rightClick(_ target: Target) async throws {
        try ElementResolver.requireTrust()
        let r = try ElementResolver.resolve(target: target, in: handle.pid)
        guard let f = r.frame else { throw PryError.noFrame(target) }
        try EventInjector.rightClick(at: CGPoint(x: f.midX, y: f.midY))
    }

    public func type(_ text: String) async throws {
        try ElementResolver.requireTrust()
        try EventInjector.type(text: text)
    }

    public func key(_ combo: String) async throws {
        try ElementResolver.requireTrust()
        try EventInjector.key(combo: combo)
    }

    public func drag(from: Target, to: Target, steps: Int = 12) async throws {
        try ElementResolver.requireTrust()
        let rf = try ElementResolver.resolve(target: from, in: handle.pid)
        let rt = try ElementResolver.resolve(target: to, in: handle.pid)
        guard let ff = rf.frame, let tf = rt.frame else { throw PryError.noFrame(from) }
        try EventInjector.drag(
            from: CGPoint(x: ff.midX, y: ff.midY),
            to: CGPoint(x: tf.midX, y: tf.midY),
            steps: steps
        )
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
    public static func runSuite(at directory: String,
                                tag: String? = nil,
                                options: SpecRunner.Options = .init()) async throws -> [Verdict] {
        let dir = URL(fileURLWithPath: directory)
        var verdicts: [Verdict] = []
        let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil)
        var paths: [URL] = []
        while let u = enumerator?.nextObject() as? URL {
            if u.pathExtension.lowercased() == "md" { paths.append(u) }
        }
        paths.sort { $0.path < $1.path }
        for url in paths {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            guard let spec = try? SpecParser.parse(source: text, sourcePath: url.path) else { continue }
            if let tag, !spec.tags.contains(tag) { continue }
            verdicts.append(await SpecRunner(spec: spec, options: options).run())
        }
        return verdicts
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
