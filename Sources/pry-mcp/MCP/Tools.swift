import Foundation
import CoreGraphics
import ApplicationServices
import PryWire
import PryHarness
import PryRunner

/// The implementation of each pry_* MCP tool. Stateless: every call takes
/// `app` (bundle ID) and opens a short-lived harness connection.
///
/// On success, tools return a human-readable text payload. On error they
/// throw a `ToolError` that carries a `kind` string (stable) plus a message
/// and optional fix hint — mirrored into the MCP error envelope.
enum PryTools {

    enum ToolError: Error {
        case kinded(kind: String, message: String, fix: String? = nil)

        var kind: String {
            if case .kinded(let k, _, _) = self { return k }
            return "internal"
        }
        var message: String {
            if case .kinded(_, let m, _) = self { return m }
            return "\(self)"
        }
        var fix: String? {
            if case .kinded(_, _, let f) = self { return f }
            return nil
        }
    }

    // MARK: - Lifecycle

    /// `pry_launch` — launch by bundle ID (installed .app) or by executable path.
    struct LaunchInput: Codable {
        var app: String                 // bundle ID
        var executable_path: String?    // optional, for SwiftPM fixtures
        var args: [String]?
        var env: [String: String]?
    }
    struct LaunchOutput: Codable {
        var pid: Int
        var socket: String
        var harness_version: String
    }
    static func launch(_ input: LaunchInput) async throws -> LaunchOutput {
        let handle: AppDriver.Handle
        do {
            if let path = input.executable_path {
                handle = try AppDriver.launchByPath(
                    executablePath: path,
                    bundleID: input.app,
                    args: input.args ?? [],
                    env: input.env ?? [:]
                )
            } else {
                handle = try await AppDriver.launchByBundleID(
                    input.app,
                    args: input.args ?? [],
                    env: input.env ?? [:]
                )
            }
        } catch let e as AppDriver.DriverError {
            switch e {
            case .bundleNotFound: throw ToolError.kinded(kind: "app_not_found", message: e.description)
            case .executableNotFound: throw ToolError.kinded(kind: "app_not_found", message: e.description)
            case .harnessSocketTimeout: throw ToolError.kinded(
                kind: "harness_unreachable",
                message: e.description,
                fix: "Ensure the target app calls PryHarness.start() under #if DEBUG.")
            default: throw ToolError.kinded(kind: "internal", message: e.description)
            }
        }
        // Handshake with retry. The socket file exists after bind(), but the
        // listen() + accept loop spin-up can race our first connect — retry
        // briefly on ECONNREFUSED.
        let hello = try await handshakeWithRetry(socketPath: handle.socketPath, timeout: 2)
        return LaunchOutput(pid: Int(hello.pid), socket: handle.socketPath, harness_version: hello.harnessVersion)
    }

    private static func handshakeWithRetry(socketPath: String, timeout: TimeInterval) async throws -> PryWire.HelloResult {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                let client = try HarnessClient(connectingTo: socketPath)
                return try await client.hello(client: "pry-mcp", version: PryMCP.version)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        if let e = lastError as? HarnessClient.ClientError {
            throw ToolError.kinded(kind: "harness_unreachable", message: e.description,
                                   fix: "Ensure the target app calls PryHarness.start() under #if DEBUG.")
        }
        throw ToolError.kinded(kind: "harness_unreachable", message: "harness handshake timed out at \(socketPath)")
    }

    /// `pry_terminate` — send SIGTERM to the target.
    struct TerminateInput: Codable { var app: String }
    struct TerminateOutput: Codable { var ok: Bool }
    static func terminate(_ input: TerminateInput) async throws -> TerminateOutput {
        // Best-effort: find PID via NSRunningApplication or via hello, then kill.
        if let handle = try? AppDriver.attach(bundleID: input.app) {
            AppDriver.terminate(handle)
            return TerminateOutput(ok: true)
        }
        return TerminateOutput(ok: false)
    }

    // MARK: - State

    struct StateInput: Codable {
        var app: String
        var viewmodel: String
        var path: String?
    }
    struct StateOutput: Codable {
        var value: PryWire.AnyCodable?
        var keys: [String: PryWire.AnyCodable]?
    }
    static func state(_ input: StateInput) async throws -> StateOutput {
        let client = try await harnessConnection(for: input.app)
        do {
            let result = try await client.readState(viewmodel: input.viewmodel, path: input.path)
            return StateOutput(value: result.value, keys: result.keys)
        } catch let e as HarnessClient.ClientError {
            throw Self.translate(e)
        }
    }

    // MARK: - Control

    struct TargetSpec: Codable {
        var id: String?
        var role: String?
        var label: String?
        var label_matches: String?
        var tree_path: String?
        var point: PointSpec?
    }
    struct PointSpec: Codable {
        var x: Double
        var y: Double
    }

    static func parseTarget(_ spec: TargetSpec) throws -> Target {
        if let id = spec.id { return .id(id) }
        if let role = spec.role, let label = spec.label { return .roleLabel(role: role, label: label) }
        if let label = spec.label { return .label(label) }
        if let lm = spec.label_matches { return .labelMatches(lm) }
        if let tp = spec.tree_path { return .treePath(tp) }
        if let p = spec.point { return .point(x: CGFloat(p.x), y: CGFloat(p.y)) }
        throw ToolError.kinded(kind: "invalid_params",
                               message: "target must specify one of: id, role+label, label, label_matches, tree_path, point")
    }

    struct ClickInput: Codable {
        var app: String
        var target: TargetSpec
        var modifiers: [String]?
    }
    struct ClickOutput: Codable {
        var resolved: ResolvedOutput
    }
    struct ResolvedOutput: Codable {
        var role: String
        var label: String?
        var id: String?
        var frame: [Double]?
    }

    static func click(_ input: ClickInput) async throws -> ClickOutput {
        let target = try parseTarget(input.target)
        let pid = try await harnessHello(app: input.app).pid
        let resolved: Resolved
        do {
            resolved = try ElementResolver.resolve(target: target, in: pid)
        } catch let e as ResolveError {
            throw Self.translate(e)
        }
        guard let frame = resolved.frame else {
            throw ToolError.kinded(kind: "resolution_empty",
                                   message: "resolved element has no frame")
        }
        let mods = EventInjector.parseModifiers(input.modifiers ?? [])
        try EventInjector.click(at: CGPoint(x: frame.midX, y: frame.midY), modifiers: mods)
        return ClickOutput(resolved: ResolvedOutput(
            role: resolved.role,
            label: resolved.label,
            id: resolved.identifier,
            frame: [frame.origin.x, frame.origin.y, frame.width, frame.height]
        ))
    }

    struct TypeInput: Codable {
        var app: String
        var text: String
    }
    struct TypeOutput: Codable { var chars_sent: Int }
    static func typeText(_ input: TypeInput) async throws -> TypeOutput {
        _ = try await harnessHello(app: input.app) // ensure harness is alive / AX trust checked
        try ElementResolver.requireTrust()
        try EventInjector.type(text: input.text)
        return TypeOutput(chars_sent: input.text.count)
    }

    struct KeyInput: Codable {
        var app: String
        var combo: String
        var `repeat`: Int?
    }
    struct KeyOutput: Codable { var ok: Bool }
    static func key(_ input: KeyInput) async throws -> KeyOutput {
        _ = try await harnessHello(app: input.app)
        try ElementResolver.requireTrust()
        let n = input.repeat ?? 1
        if n > 1 { try EventInjector.keyRepeat(combo: input.combo, count: n) }
        else { try EventInjector.key(combo: input.combo) }
        return KeyOutput(ok: true)
    }

    struct LongPressInput: Codable { var app: String; var target: TargetSpec; var dwell_ms: Int? }
    static func longPress(_ input: LongPressInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let t = try parseTarget(input.target)
        let r = try ElementResolver.resolve(target: t, in: hello.pid)
        guard let f = r.frame else { throw ToolError.kinded(kind: "resolution_empty", message: "no frame") }
        try EventInjector.longPress(at: CGPoint(x: f.midX, y: f.midY), dwellMs: input.dwell_ms ?? 800)
        return KeyOutput(ok: true)
    }

    struct MagnifyInput: Codable { var app: String; var target: TargetSpec; var delta: Int }
    static func magnify(_ input: MagnifyInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let t = try parseTarget(input.target)
        let r = try ElementResolver.resolve(target: t, in: hello.pid)
        guard let f = r.frame else { throw ToolError.kinded(kind: "resolution_empty", message: "no frame") }
        try EventInjector.magnify(at: CGPoint(x: f.midX, y: f.midY), delta: Int32(input.delta))
        return KeyOutput(ok: true)
    }

    struct OpenFileInput: Codable { var app: String; var path: String }
    static func openFile(_ input: OpenFileInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        _ = try await harnessHello(app: input.app)
        let pry = try await pryActor(for: input.app)
        try await pry.openFile(input.path)
        return KeyOutput(ok: true)
    }

    struct SaveFileInput: Codable { var app: String; var path: String }
    static func saveFile(_ input: SaveFileInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        _ = try await harnessHello(app: input.app)
        let pry = try await pryActor(for: input.app)
        try await pry.saveFile(input.path)
        return KeyOutput(ok: true)
    }

    struct PanelAcceptInput: Codable { var app: String; var button: String? }
    static func panelAccept(_ input: PanelAcceptInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        _ = try await harnessHello(app: input.app)
        let pry = try await pryActor(for: input.app)
        try await pry.acceptPanel(button: input.button)
        return KeyOutput(ok: true)
    }

    struct PanelCancelInput: Codable { var app: String }
    static func panelCancel(_ input: PanelCancelInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        _ = try await harnessHello(app: input.app)
        try EventInjector.key(combo: "esc")
        return KeyOutput(ok: true)
    }

    /// Build a transient Pry actor over the existing harness socket. The MCP
    /// tools today open a fresh client per call (`harnessHello`); for panel
    /// helpers we want the higher-level Pry surface, so attach quickly.
    private static func pryActor(for bundleID: String) async throws -> Pry {
        return try await Pry.attach(to: bundleID)
    }

    struct SelectMenuInput: Codable { var app: String; var path: [String] }
    static func selectMenu(_ input: SelectMenuInput) async throws -> KeyOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let pid = hello.pid
        let appEl = AXUIElementCreateApplication(pid)
        var attr: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXMenuBarAttribute as CFString, &attr) == .success,
              let menuBar = attr else {
            throw ToolError.kinded(kind: "no_menu_bar", message: "app has no menu bar")
        }
        var current: AXUIElement = menuBar as! AXUIElement
        for (i, segment) in input.path.enumerated() {
            var childAttr: CFTypeRef?
            AXUIElementCopyAttributeValue(current, kAXChildrenAttribute as CFString, &childAttr)
            guard let kids = childAttr as? [AXUIElement] else {
                throw ToolError.kinded(kind: "menu_walk_failed",
                                       message: "no children at '\(input.path.prefix(i).joined(separator: " > "))'")
            }
            guard let next = kids.first(where: { el -> Bool in
                var t: CFTypeRef?
                AXUIElementCopyAttributeValue(el, kAXTitleAttribute as CFString, &t)
                return (t as? String) == segment
            }) else {
                throw ToolError.kinded(kind: "menu_segment_not_found",
                                       message: "segment '\(segment)' not found")
            }
            AXUIElementPerformAction(next, kAXPressAction as CFString)
            current = next
            if i < input.path.count - 1 {
                var c: CFTypeRef?
                AXUIElementCopyAttributeValue(next, kAXChildrenAttribute as CFString, &c)
                if let cs = c as? [AXUIElement],
                   let menu = cs.first(where: { el in
                       var r: CFTypeRef?
                       AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &r)
                       return (r as? String) == "AXMenu"
                   }) {
                    current = menu
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
        return KeyOutput(ok: true)
    }

    // MARK: - Drag / scroll / expect_change

    struct DragInput: Codable {
        var app: String
        var from: TargetSpec
        var to: TargetSpec
        var steps: Int?
    }
    struct DragOutput: Codable { var ok: Bool }
    static func drag(_ input: DragInput) async throws -> DragOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let f = try parseTarget(input.from)
        let t = try parseTarget(input.to)
        let rf = try ElementResolver.resolve(target: f, in: hello.pid)
        let rt = try ElementResolver.resolve(target: t, in: hello.pid)
        guard let ff = rf.frame, let tf = rt.frame else {
            throw ToolError.kinded(kind: "resolution_empty",
                                   message: "drag endpoints have no frame")
        }
        try EventInjector.drag(
            from: CGPoint(x: ff.midX, y: ff.midY),
            to: CGPoint(x: tf.midX, y: tf.midY),
            steps: input.steps ?? 12
        )
        return DragOutput(ok: true)
    }

    struct ScrollInput: Codable {
        var app: String
        var target: TargetSpec
        var direction: String  // up | down | left | right
        var amount: Int?
    }
    struct ScrollOutput: Codable { var ok: Bool }
    static func scroll(_ input: ScrollInput) async throws -> ScrollOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let target = try parseTarget(input.target)
        let r = try ElementResolver.resolve(target: target, in: hello.pid)
        guard let f = r.frame else {
            throw ToolError.kinded(kind: "resolution_empty",
                                   message: "scroll target has no frame")
        }
        let p = CGPoint(x: f.midX, y: f.midY)
        let mag = Int32(input.amount ?? 3)
        let (dx, dy): (Int32, Int32)
        switch input.direction {
        case "up": (dx, dy) = (0, mag)
        case "down": (dx, dy) = (0, -mag)
        case "left": (dx, dy) = (mag, 0)
        case "right": (dx, dy) = (-mag, 0)
        default:
            throw ToolError.kinded(kind: "invalid_params",
                                   message: "direction must be up|down|left|right")
        }
        try EventInjector.scroll(at: p, dx: dx, dy: dy)
        return ScrollOutput(ok: true)
    }

    // MARK: - Tree / find / wait_for / assert / snapshot

    struct TreeInput: Codable {
        var app: String
        var window: WindowSpec?
    }
    struct WindowSpec: Codable {
        var title: String?
        var title_matches: String?
    }
    struct TreeOutput: Codable { var yaml: String }
    static func tree(_ input: TreeInput) async throws -> TreeOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let filter = input.window.map { WindowFilter(title: $0.title, titleMatches: $0.title_matches) }
        let tree = AXTreeWalker.snapshot(pid: hello.pid, window: filter)
        return TreeOutput(yaml: AXTreeWalker.renderYAML(tree))
    }

    struct FindInput: Codable {
        var app: String
        var target: TargetSpec
    }
    struct FindMatch: Codable {
        var role: String
        var label: String?
        var id: String?
        var frame: [Double]?
        var enabled: Bool
    }
    struct FindOutput: Codable { var matches: [FindMatch] }
    static func find(_ input: FindInput) async throws -> FindOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let target = try parseTarget(input.target)
        let tree = AXTreeWalker.snapshot(pid: hello.pid)
        var matches: [FindMatch] = []
        collectMatches(tree, target: target, into: &matches)
        return FindOutput(matches: matches)
    }

    private static func collectMatches(_ node: AXNode, target: Target, into out: inout [FindMatch]) {
        let hit: Bool
        switch target {
        case .id(let s): hit = node.identifier == s
        case .roleLabel(let r, let l): hit = node.role == r && node.label == l
        case .label(let l): hit = node.label == l
        case .labelMatches(let re):
            if let lbl = node.label, let rx = try? NSRegularExpression(pattern: re) {
                hit = rx.firstMatch(in: lbl, range: NSRange(lbl.startIndex..., in: lbl)) != nil
            } else { hit = false }
        default: hit = false
        }
        if hit {
            out.append(FindMatch(role: node.role, label: node.label, id: node.identifier,
                                 frame: node.frame, enabled: node.enabled))
        }
        for c in node.children { collectMatches(c, target: target, into: &out) }
    }

    struct SnapshotInput: Codable {
        var app: String
        var path: String?
    }
    struct SnapshotOutput: Codable { var path: String }
    static func snapshot(_ input: SnapshotInput) async throws -> SnapshotOutput {
        try ElementResolver.requireTrust()
        let hello = try await harnessHello(app: input.app)
        let targetPath = input.path ?? NSTemporaryDirectory() + "pry-snap-\(UUID().uuidString).png"
        guard let data = await WindowCapture.capturePNG(pid: hello.pid) else {
            throw ToolError.kinded(kind: "snapshot_failed",
                                   message: "could not capture window for pid \(hello.pid)",
                                   fix: "Grant Screen Recording permission to pry-mcp's parent process.")
        }
        try data.write(to: URL(fileURLWithPath: targetPath))
        return SnapshotOutput(path: targetPath)
    }

    // MARK: - Clock / animations / pasteboard

    struct ClockAdvanceInput: Codable { var app: String; var seconds: Double }
    struct ClockAdvanceOutput: Codable { var iso8601: String; var fired_callbacks: Int }
    static func clockAdvance(_ input: ClockAdvanceInput) async throws -> ClockAdvanceOutput {
        let client = try await harnessConnection(for: input.app)
        let r = try await client.clockAdvance(seconds: input.seconds)
        return ClockAdvanceOutput(iso8601: r.iso8601, fired_callbacks: r.firedCallbacks)
    }

    struct ClockSetInput: Codable { var app: String; var iso8601: String; var paused: Bool? }
    static func clockSet(_ input: ClockSetInput) async throws -> ClockAdvanceOutput {
        let client = try await harnessConnection(for: input.app)
        let r = try await client.clockSet(iso8601: input.iso8601, paused: input.paused)
        return ClockAdvanceOutput(iso8601: r.iso8601, fired_callbacks: r.firedCallbacks)
    }

    struct ClockGetInput: Codable { var app: String }
    struct ClockGetOutput: Codable { var iso8601: String; var paused: Bool }
    static func clockGet(_ input: ClockGetInput) async throws -> ClockGetOutput {
        let client = try await harnessConnection(for: input.app)
        let r = try await client.clockGet()
        return ClockGetOutput(iso8601: r.iso8601, paused: r.paused)
    }

    struct AnimationsInput: Codable { var app: String; var enabled: Bool }
    struct AnimationsOutput: Codable { var enabled: Bool }
    static func setAnimations(_ input: AnimationsInput) async throws -> AnimationsOutput {
        let client = try await harnessConnection(for: input.app)
        let r = try await client.setAnimations(enabled: input.enabled)
        return AnimationsOutput(enabled: r.enabled)
    }

    struct PasteboardReadInput: Codable { var app: String }
    struct PasteboardReadOutput: Codable { var string: String?; var types: [String] }
    static func pasteboardRead(_ input: PasteboardReadInput) async throws -> PasteboardReadOutput {
        let client = try await harnessConnection(for: input.app)
        let r = try await client.readPasteboard()
        return PasteboardReadOutput(string: r.string, types: r.types)
    }

    struct PasteboardWriteInput: Codable { var app: String; var string: String }
    struct PasteboardWriteOutput: Codable { var ok: Bool }
    static func pasteboardWrite(_ input: PasteboardWriteInput) async throws -> PasteboardWriteOutput {
        let client = try await harnessConnection(for: input.app)
        _ = try await client.writePasteboard(string: input.string)
        return PasteboardWriteOutput(ok: true)
    }

    // MARK: - Logs

    struct LogsInput: Codable {
        var app: String
        var since: String?
        var subsystem: String?
    }
    struct LogsOutput: Codable {
        var lines: [PryWire.LogLine]
        var cursor: String
    }
    static func logs(_ input: LogsInput) async throws -> LogsOutput {
        let client = try await harnessConnection(for: input.app)
        do {
            let result = try await client.readLogs(since: input.since, subsystem: input.subsystem)
            return LogsOutput(lines: result.lines, cursor: result.cursor)
        } catch let e as HarnessClient.ClientError {
            throw Self.translate(e)
        }
    }

    // MARK: - Spec execution

    struct RunSpecInput: Codable {
        var source: String?         // "path" | "inline" ; defaults to path if `path` set
        var path: String?
        var markdown: String?
        var verdicts_dir: String?
        var snapshots: String?      // "always" | "on_failure"
    }
    struct RunSpecOutput: Codable {
        var status: String
        var verdict_path: String?
        var verdict_markdown: String
    }
    static func runSpec(_ input: RunSpecInput) async throws -> RunSpecOutput {
        let spec: Spec
        if let p = input.path {
            let url = URL(fileURLWithPath: p).standardizedFileURL
            guard let text = try? String(contentsOf: url, encoding: .utf8) else {
                throw ToolError.kinded(kind: "spec_parse_error", message: "cannot read \(url.path)")
            }
            do {
                spec = try SpecParser.parse(source: text, sourcePath: url.path)
            } catch {
                throw ToolError.kinded(kind: "spec_parse_error", message: "\(error)")
            }
        } else if let md = input.markdown {
            do {
                spec = try SpecParser.parse(source: md, sourcePath: nil)
            } catch {
                throw ToolError.kinded(kind: "spec_parse_error", message: "\(error)")
            }
        } else {
            throw ToolError.kinded(kind: "invalid_params", message: "pry_run_spec needs `path` or `markdown`")
        }

        let opts = SpecRunner.Options(
            verdictsDir: URL(fileURLWithPath: input.verdicts_dir ?? "./pry-verdicts"),
            alwaysSnapshot: input.snapshots == "always"
        )
        let runner = SpecRunner(spec: spec, options: opts)
        let verdict = await runner.run()
        let md = VerdictReporter.render(verdict)

        var verdictPath: String?
        if let dir = verdict.attachmentsDir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appendingPathComponent("verdict.md")
            try? md.write(to: url, atomically: true, encoding: .utf8)
            verdictPath = url.path
        }

        return RunSpecOutput(
            status: verdict.status.rawValue,
            verdict_path: verdictPath,
            verdict_markdown: md
        )
    }

    struct RunSuiteInput: Codable {
        var path: String
        var tag: String?
        var verdicts_dir: String?
        var parallel: Int?
        var retry_failed: Int?
        var junit: String?
        var tap: String?
        var summary_md: String?
    }
    struct SuiteEntry: Codable {
        var spec: String
        var status: String
        var duration: Double
        var failed_at_step: Int?
    }
    struct RunSuiteOutput: Codable {
        var total: Int
        var passed: Int
        var failed: Int
        var errored: Int
        var verdicts: [SuiteEntry]
    }
    static func runSuite(_ input: RunSuiteInput) async throws -> RunSuiteOutput {
        let opts = SpecRunner.Options(
            verdictsDir: URL(fileURLWithPath: input.verdicts_dir ?? "./pry-verdicts")
        )
        let verdicts = try await Pry.runSuite(
            at: input.path,
            tag: input.tag,
            parallel: input.parallel ?? 1,
            retry: input.retry_failed ?? 0,
            options: opts
        )

        // Write each verdict.md
        for v in verdicts {
            let md = VerdictReporter.render(v)
            if let dir = v.attachmentsDir {
                try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try? md.write(to: dir.appendingPathComponent("verdict.md"), atomically: true, encoding: .utf8)
            }
        }
        // Aggregate exports
        if let path = input.junit {
            try? VerdictExporters.junit(verdicts).write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = input.tap {
            try? VerdictExporters.tap(verdicts).write(toFile: path, atomically: true, encoding: .utf8)
        }
        if let path = input.summary_md {
            try? VerdictExporters.markdownSummary(verdicts).write(toFile: path, atomically: true, encoding: .utf8)
        }

        let passed = verdicts.filter { $0.status == .passed }.count
        let failed = verdicts.filter { $0.status == .failed }.count
        let errored = verdicts.filter { $0.status == .errored || $0.status == .timedOut }.count
        let entries = verdicts.map {
            SuiteEntry(spec: $0.specID, status: $0.status.rawValue,
                       duration: $0.duration, failed_at_step: $0.failedAtStep)
        }
        return RunSuiteOutput(total: verdicts.count, passed: passed, failed: failed,
                              errored: errored, verdicts: entries)
    }

    struct ListSpecsInput: Codable {
        var path: String
    }
    struct SpecListEntry: Codable {
        var path: String
        var id: String
        var tags: [String]
    }
    struct ListSpecsOutput: Codable {
        var specs: [SpecListEntry]
    }
    static func listSpecs(_ input: ListSpecsInput) async throws -> ListSpecsOutput {
        let dir = URL(fileURLWithPath: input.path).standardizedFileURL
        var entries: [SpecListEntry] = []
        if let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) {
            while let u = enumerator.nextObject() as? URL {
                guard u.pathExtension.lowercased() == "md" else { continue }
                if let src = try? String(contentsOf: u, encoding: .utf8),
                   let spec = try? SpecParser.parse(source: src, sourcePath: u.path) {
                    entries.append(SpecListEntry(path: u.path, id: spec.id, tags: spec.tags))
                }
            }
        }
        entries.sort(by: { $0.path < $1.path })
        return ListSpecsOutput(specs: entries)
    }

    // MARK: - Helpers

    private static func harnessConnection(for bundle: String) async throws -> HarnessClient {
        let path = PryHarness.socketPath(for: bundle)
        do {
            let client = try HarnessClient(connectingTo: path)
            _ = try await client.hello(client: "pry-mcp", version: PryMCP.version)
            return client
        } catch let e as HarnessClient.ClientError {
            throw Self.translate(e)
        }
    }

    private static func harnessHello(app: String) async throws -> PryWire.HelloResult {
        let path = PryHarness.socketPath(for: app)
        let client = try HarnessClient(connectingTo: path)
        return try await client.hello(client: "pry-mcp", version: PryMCP.version)
    }

    static func translate(_ e: HarnessClient.ClientError) -> ToolError {
        switch e {
        case .connect:
            return .kinded(kind: "harness_unreachable",
                           message: e.description,
                           fix: "Launch the app first via pry_launch, or ensure PryHarness.start() is called.")
        case .rpcError(let err):
            let kind: String
            switch err.code {
            case PryWire.RPCError.viewmodelNotRegistered: kind = "viewmodel_not_registered"
            case PryWire.RPCError.pathNotFound: kind = "path_not_found"
            case PryWire.RPCError.methodNotFound: kind = "not_implemented"
            case PryWire.RPCError.invalidParams: kind = "invalid_params"
            default: kind = "internal"
            }
            return .kinded(kind: kind, message: err.message)
        default:
            return .kinded(kind: "internal", message: e.description)
        }
    }

    static func translate(_ e: ResolveError) -> ToolError {
        switch e {
        case .accessibilityNotTrusted:
            return .kinded(kind: "ax_permission_denied",
                           message: e.description,
                           fix: "System Settings → Privacy & Security → Accessibility")
        case .noMatch:
            return .kinded(kind: "resolution_empty", message: e.description)
        case .ambiguous:
            return .kinded(kind: "resolution_ambiguous", message: e.description,
                           fix: "Narrow the target via `id` (highest precedence) or add a `role:` constraint.")
        case .windowNotFound:
            return .kinded(kind: "window_not_found", message: e.description)
        }
    }
}

enum PryMCP {
    static let version = "0.1.0-dev"
}
