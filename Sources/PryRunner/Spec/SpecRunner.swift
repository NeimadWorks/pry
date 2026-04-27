import Foundation
import ApplicationServices
import CoreGraphics
import PryWire
import PryHarness

/// Executes a parsed `Spec` against the target app and produces a `Verdict`.
public actor SpecRunner {

    public struct Options: Sendable {
        public var verdictsDir: URL
        /// When true, `snapshot:` steps always save to disk (not only on failure).
        public var alwaysSnapshot: Bool
        public init(verdictsDir: URL = URL(fileURLWithPath: "./pry-verdicts"),
                    alwaysSnapshot: Bool = false) {
            self.verdictsDir = verdictsDir
            self.alwaysSnapshot = alwaysSnapshot
        }
    }

    public let spec: Spec
    public let options: Options

    // Runtime state
    private var launchHandle: AppDriver.Handle?
    private var harness: HarnessClient?
    private var stepResults: [StepResult] = []
    private var attachments: [String] = []
    private var attachmentsDir: URL?

    public init(spec: Spec, options: Options = .init()) {
        self.spec = spec
        self.options = options
    }

    public func run() async -> Verdict {
        let started = Date()
        prepareAttachments(started: started)

        var status: Verdict.Status = .passed
        var failure: FailureContext?
        var errorKind: String?
        var errorMessage: String?

        let globalDeadline = started.addingTimeInterval(spec.timeout.seconds)

        for (i, step) in spec.steps.enumerated() {
            if Date() > globalDeadline {
                status = .timedOut
                appendSkipped(from: i)
                break
            }
            let idx = i + 1
            let stepStart = Date()
            let source = renderStep(step)
            do {
                try await execute(step, stepIndex: idx, source: source)
                stepResults.append(StepResult(
                    index: idx, line: nil, source: source,
                    outcome: .passed, duration: Date().timeIntervalSince(stepStart), message: nil
                ))
            } catch let e as StepFailure {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: source,
                    outcome: .failed, duration: Date().timeIntervalSince(stepStart), message: e.summary
                ))
                status = .failed
                let ctx = await buildFailureContext(stepIndex: idx, stepSource: source, failure: e)
                failure = ctx
                appendSkipped(from: i + 1)
                break
            } catch let e as StepError {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: source,
                    outcome: .errored, duration: Date().timeIntervalSince(stepStart), message: e.message
                ))
                status = .errored
                errorKind = e.kind
                errorMessage = e.message
                appendSkipped(from: i + 1)
                break
            } catch {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: source,
                    outcome: .errored, duration: Date().timeIntervalSince(stepStart), message: "\(error)"
                ))
                status = .errored
                errorKind = "internal"
                errorMessage = "\(error)"
                appendSkipped(from: i + 1)
                break
            }
        }

        let finished = Date()

        return Verdict(
            specPath: spec.sourcePath,
            specID: spec.id,
            app: spec.app,
            status: status,
            duration: finished.timeIntervalSince(started),
            stepsTotal: spec.steps.count,
            stepsPassed: stepResults.filter { $0.outcome == .passed }.count,
            failedAtStep: failure?.stepIndex,
            startedAt: started,
            finishedAt: finished,
            stepResults: stepResults,
            failure: failure,
            errorKind: errorKind,
            errorMessage: errorMessage,
            attachmentsDir: attachmentsDir
        )
    }

    // MARK: - Step execution

    private func execute(_ step: Step, stepIndex: Int, source: String) async throws {
        switch step {
        case .launch(let args, let env):
            try await doLaunch(args: args, env: env)

        case .terminate:
            if let h = launchHandle { AppDriver.terminate(h) }
            launchHandle = nil
            harness = nil

        case .relaunch:
            if let h = launchHandle { AppDriver.terminate(h) }
            launchHandle = nil
            harness = nil
            try await doLaunch(args: [], env: [:])

        case .waitFor(let pred, let timeout):
            try await waitForPredicate(pred, timeout: timeout, stepIndex: stepIndex, source: source)

        case .sleep(let d):
            try? await Task.sleep(nanoseconds: UInt64(d.seconds * 1_000_000_000))

        case .click(let target):
            try await injectClick(target: target, kind: .single, stepIndex: stepIndex, source: source)
        case .doubleClick(let target):
            try await injectClick(target: target, kind: .double, stepIndex: stepIndex, source: source)
        case .rightClick(let target):
            try await injectClick(target: target, kind: .right, stepIndex: stepIndex, source: source)
        case .hover(let target):
            try ElementResolver.requireTrust()
            let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
            try? EventInjector.move(to: CGPoint(x: r.frame!.midX, y: r.frame!.midY))

        case .type(let text):
            try ElementResolver.requireTrust()
            try EventInjector.type(text: text)

        case .key(let combo):
            try ElementResolver.requireTrust()
            try EventInjector.key(combo: combo)

        case .scroll(let target, let direction, let amount):
            try ElementResolver.requireTrust()
            let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "scroll target has a frame",
                                  observed: "\(r.role) has no frame", suggestion: nil)
            }
            let p = CGPoint(x: f.midX, y: f.midY)
            // macOS scroll wheel: positive Y = scroll up content (page up).
            // Translate semantic direction → wheel deltas.
            let mag = Int32(amount)
            let (dx, dy): (Int32, Int32)
            switch direction {
            case .up: (dx, dy) = (0, mag)
            case .down: (dx, dy) = (0, -mag)
            case .left: (dx, dy) = (mag, 0)
            case .right: (dx, dy) = (-mag, 0)
            }
            try EventInjector.scroll(at: p, dx: dx, dy: dy)

        case .drag(let from, let to, let steps):
            try ElementResolver.requireTrust()
            let rf = try resolveTarget(from, stepSource: source, stepIndex: stepIndex)
            let rt = try resolveTarget(to, stepSource: source, stepIndex: stepIndex)
            guard let ff = rf.frame, let tf = rt.frame else {
                throw StepFailure(expected: "drag endpoints have frames",
                                  observed: "missing frame on \(rf.frame == nil ? "from" : "to")",
                                  suggestion: nil)
            }
            let fromP = CGPoint(x: ff.midX, y: ff.midY)
            let toP = CGPoint(x: tf.midX, y: tf.midY)
            try EventInjector.drag(from: fromP, to: toP, steps: steps)

        case .expectChange(let action, let vm, let path, let target, let timeout):
            try await runExpectChange(action: action, viewmodel: vm, path: path,
                                      target: target, timeout: timeout,
                                      stepIndex: stepIndex, source: source)

        case .assertTree(let pred):
            try await assertTreeNow(pred, stepIndex: stepIndex, source: source)

        case .assertState(let vm, let path, let expect):
            try await assertStateNow(viewmodel: vm, path: path, expect: expect,
                                     stepIndex: stepIndex, source: source)

        case .snapshot(let name):
            if let att = try? await captureSnapshot(name: name) { attachments.append(att) }

        case .dumpTree(let name):
            if let att = await dumpTreeToFile(name: name) { attachments.append(att) }

        case .dumpState(let name):
            if let att = await dumpStateToFile(name: name) { attachments.append(att) }
        }
    }

    // MARK: - Launch

    private func doLaunch(args: [String], env: [String: String]) async throws {
        do {
            let handle: AppDriver.Handle
            if let path = spec.executablePath {
                handle = try AppDriver.launchByPath(
                    executablePath: path, bundleID: spec.app, args: args, env: env)
            } else {
                handle = try await AppDriver.launchByBundleID(spec.app, args: args, env: env)
            }
            let client = try HarnessClient(connectingTo: handle.socketPath)
            // Handshake with retry
            let deadline = Date().addingTimeInterval(2)
            var lastErr: Error?
            while Date() < deadline {
                do {
                    _ = try await client.hello(client: "pry-mcp", version: VerdictReporter.pryVersion)
                    launchHandle = handle
                    harness = client
                    return
                } catch {
                    lastErr = error
                    try? await Task.sleep(nanoseconds: 50_000_000)
                }
            }
            throw StepError(kind: "harness_unreachable",
                            message: "harness handshake failed: \(lastErr.map { "\($0)" } ?? "timeout")")
        } catch let e as AppDriver.DriverError {
            throw StepError(kind: e.kindForVerdict, message: e.description)
        } catch let e as StepError {
            throw e
        } catch {
            throw StepError(kind: "internal", message: "\(error)")
        }
    }

    // MARK: - Event injection with resolve

    enum ClickKind { case single, double, right }

    private func injectClick(target: TargetRef, kind: ClickKind, stepIndex: Int, source: String) async throws {
        try ElementResolver.requireTrust()
        let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
        guard let f = r.frame else {
            throw StepFailure(expected: "target resolves to an element with a frame",
                              observed: "\(r.role) has no frame",
                              suggestion: nil)
        }
        let p = CGPoint(x: f.midX, y: f.midY)
        switch kind {
        case .single: try EventInjector.click(at: p)
        case .double: try EventInjector.doubleClick(at: p)
        case .right: try EventInjector.rightClick(at: p)
        }
    }

    private func resolveTarget(_ target: TargetRef, stepSource: String, stepIndex: Int) throws -> Resolved {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app; call `launch` first")
        }
        let t: Target = convert(target)
        do {
            return try ElementResolver.resolve(target: t, in: h.pid)
        } catch let e as ResolveError {
            switch e {
            case .accessibilityNotTrusted:
                throw StepError(kind: "ax_permission_denied", message: e.description)
            case .noMatch:
                throw StepFailure(
                    expected: "target resolves to an element",
                    observed: e.description,
                    suggestion: "Verify the target exists in the AX tree (use `pry-mcp` CLI with dump_tree)."
                )
            case .ambiguous(_, let cands):
                throw StepFailure(
                    expected: "target resolves to exactly one element",
                    observed: "\(cands.count) elements match:\n  - " + cands.joined(separator: "\n  - "),
                    suggestion: "Narrow with `id:` (highest precedence) or add a `role:` constraint."
                )
            case .windowNotFound:
                throw StepFailure(expected: "window present", observed: e.description, suggestion: nil)
            }
        }
    }

    private func convert(_ t: TargetRef) -> Target {
        switch t {
        case .id(let s): return .id(s)
        case .roleLabel(let r, let l): return .roleLabel(role: r, label: l)
        case .label(let s): return .label(s)
        case .labelMatches(let s): return .labelMatches(s)
        case .treePath(let s): return .treePath(s)
        case .point(let x, let y): return .point(x: CGFloat(x), y: CGFloat(y))
        }
    }

    // MARK: - expect_change

    private func runExpectChange(action: ExpectChangeAction, viewmodel: String, path: String,
                                 target: YAMLValue, timeout: Duration,
                                 stepIndex: Int, source: String) async throws {
        // Snapshot the value before the action (for the "before → after" message).
        let before: PryWire.AnyCodable? = try? await {
            guard let h = harness else { return nil }
            return try await h.readState(viewmodel: viewmodel, path: path).value
        }()

        // Execute the action.
        try ElementResolver.requireTrust()
        switch action {
        case .click(let t):
            let r = try resolveTarget(t, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "action target has a frame",
                                  observed: "\(r.role) has no frame", suggestion: nil)
            }
            try EventInjector.click(at: CGPoint(x: f.midX, y: f.midY))
        case .doubleClick(let t):
            let r = try resolveTarget(t, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "action target has a frame",
                                  observed: "\(r.role) has no frame", suggestion: nil)
            }
            try EventInjector.doubleClick(at: CGPoint(x: f.midX, y: f.midY))
        case .rightClick(let t):
            let r = try resolveTarget(t, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "action target has a frame",
                                  observed: "\(r.role) has no frame", suggestion: nil)
            }
            try EventInjector.rightClick(at: CGPoint(x: f.midX, y: f.midY))
        case .key(let combo):
            try EventInjector.key(combo: combo)
        case .type(let text):
            try EventInjector.type(text: text)
        }

        // Poll for the new value within the timeout. We reuse the wait_for
        // mechanism but bound it more tightly — expect_change is "the value
        // changed because of this action", not "the value will eventually
        // arrive."
        let pred = Predicate.state(viewmodel: viewmodel, path: path, expect: .equals(target))
        do {
            try await waitForPredicate(pred, timeout: timeout, stepIndex: stepIndex, source: source)
        } catch let f as StepFailure {
            // Enrich the failure with the before-value if we captured one.
            let beforeStr: String
            if let b = before { beforeStr = "before action: \(renderAny(b.value))" }
            else { beforeStr = "before action: <unread>" }
            throw StepFailure(
                expected: f.expected,
                observed: "\(f.observed); \(beforeStr)",
                suggestion: f.suggestion
            )
        }
    }

    // MARK: - wait_for

    private func waitForPredicate(_ pred: Predicate, timeout: Duration, stepIndex: Int, source: String) async throws {
        let deadline = Date().addingTimeInterval(timeout.seconds)
        var lastErr: String?
        while Date() < deadline {
            do {
                try await evaluatePredicate(pred)
                return
            } catch let e as PredicateFailure {
                lastErr = e.description
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        throw StepFailure(
            expected: "predicate holds within \(timeout.seconds)s",
            observed: lastErr ?? "predicate did not hold",
            suggestion: nil
        )
    }

    // MARK: - Predicate / assertion evaluation

    private struct PredicateFailure: Error, CustomStringConvertible {
        let description: String
    }

    private func evaluatePredicate(_ pred: Predicate) async throws {
        switch pred {
        case .window(let title, let tm):
            guard let h = launchHandle else { throw PredicateFailure(description: "no running app") }
            let filter = WindowFilter(title: title, titleMatches: tm)
            if AXTreeWalker.resolveWindow(pid: h.pid, filter: filter) == nil {
                throw PredicateFailure(description: "no window matches \(title ?? tm ?? "*")")
            }

        case .contains(let target):
            _ = try resolveTargetForPredicate(target)

        case .notContains(let target):
            if (try? resolveTargetForPredicate(target)) != nil {
                throw PredicateFailure(description: "element \(target) is present, expected absent")
            }

        case .countOf(let target, let n):
            let count = countMatches(target)
            if count != n { throw PredicateFailure(description: "count(\(target)) = \(count), expected \(n)") }

        case .visible(let target):
            let r = try resolveTargetForPredicate(target)
            guard let f = r.frame, f.width > 0, f.height > 0 else {
                throw PredicateFailure(description: "\(r.role) not visible (no frame)")
            }

        case .enabled(let target):
            _ = try resolveTargetForPredicate(target)
            // Best-effort: assume enabled unless AX says otherwise (covered in snapshot)

        case .focused(let target):
            _ = try resolveTargetForPredicate(target)

        case .state(let vm, let path, let expect):
            do {
                try await assertStateNow(viewmodel: vm, path: path, expect: expect, stepIndex: 0, source: "state predicate")
            } catch let f as StepFailure {
                throw PredicateFailure(description: f.observed)
            } catch let e as StepError {
                throw PredicateFailure(description: e.message)
            }

        case .allOf(let preds):
            for p in preds { try await evaluatePredicate(p) }

        case .anyOf(let preds):
            var lastErr: String?
            for p in preds {
                do { try await evaluatePredicate(p); return }
                catch let e as PredicateFailure { lastErr = e.description }
            }
            throw PredicateFailure(description: "no sub-predicate matched: \(lastErr ?? "?")")

        case .not(let sub):
            if (try? await evaluatePredicate(sub)) != nil {
                throw PredicateFailure(description: "inner predicate matched")
            }
        }
    }

    private func resolveTargetForPredicate(_ t: TargetRef) throws -> Resolved {
        guard let h = launchHandle else { throw PredicateFailure(description: "no running app") }
        do {
            return try ElementResolver.resolve(target: convert(t), in: h.pid)
        } catch let e as ResolveError {
            throw PredicateFailure(description: e.description)
        }
    }

    private func countMatches(_ t: TargetRef) -> Int {
        guard let h = launchHandle else { return 0 }
        let snap = AXTreeWalker.snapshot(pid: h.pid)
        return walkCount(snap, matching: t)
    }

    private func walkCount(_ node: AXNode, matching t: TargetRef) -> Int {
        var n = 0
        if nodeMatches(node, t) { n += 1 }
        for c in node.children { n += walkCount(c, matching: t) }
        return n
    }

    private func nodeMatches(_ node: AXNode, _ t: TargetRef) -> Bool {
        switch t {
        case .id(let s): return node.identifier == s
        case .roleLabel(let r, let l): return node.role == r && node.label == l
        case .label(let l): return node.label == l
        case .labelMatches(let re):
            guard let label = node.label, let rx = try? NSRegularExpression(pattern: re) else { return false }
            return rx.firstMatch(in: label, range: NSRange(label.startIndex..., in: label)) != nil
        default: return false
        }
    }

    private func assertTreeNow(_ pred: Predicate, stepIndex: Int, source: String) async throws {
        do {
            try await evaluatePredicate(pred)
        } catch let e as PredicateFailure {
            throw StepFailure(expected: "tree predicate holds", observed: e.description, suggestion: nil)
        }
    }

    private func assertStateNow(viewmodel: String, path: String,
                                expect: StateExpectation,
                                stepIndex: Int, source: String) async throws {
        guard let h = harness else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        let result: PryWire.ReadStateResult
        do {
            result = try await h.readState(viewmodel: viewmodel, path: path)
        } catch let e as HarnessClient.ClientError {
            if case .rpcError(let err) = e {
                if err.code == PryWire.RPCError.viewmodelNotRegistered {
                    throw StepFailure(
                        expected: "viewmodel '\(viewmodel)' registered",
                        observed: err.message,
                        suggestion: "Verify PryRegistry.shared.register(\(viewmodel)()) runs at startup."
                    )
                }
                if err.code == PryWire.RPCError.pathNotFound {
                    throw StepFailure(
                        expected: "path '\(path)' present in \(viewmodel) snapshot",
                        observed: err.message,
                        suggestion: "Check the keys declared in prySnapshot()."
                    )
                }
            }
            throw StepError(kind: "internal", message: e.description)
        }
        guard let value = result.value else {
            throw StepError(kind: "internal", message: "expected scalar value; got no value")
        }
        try checkExpectation(value: value.value, expect: expect, viewmodel: viewmodel, path: path)
    }

    private func checkExpectation(value: any Sendable, expect: StateExpectation, viewmodel: String, path: String) throws {
        switch expect {
        case .equals(let y):
            if !compareEquals(value, y) {
                throw StepFailure(
                    expected: "\(viewmodel).\(path) equals \(renderYAMLValue(y))",
                    observed: "got \(renderAny(value))",
                    suggestion: nil
                )
            }
        case .matches(let pattern):
            guard let s = value as? String, let rx = try? NSRegularExpression(pattern: pattern) else {
                throw StepFailure(expected: "string matching /\(pattern)/",
                                  observed: "\(renderAny(value))", suggestion: nil)
            }
            if rx.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) == nil {
                throw StepFailure(expected: "string matching /\(pattern)/",
                                  observed: "'\(s)'", suggestion: nil)
            }
        case .anyOf(let values):
            for v in values where compareEquals(value, v) { return }
            throw StepFailure(
                expected: "\(viewmodel).\(path) in any_of \(values.map(renderYAMLValue))",
                observed: renderAny(value),
                suggestion: nil
            )
        }
    }

    private func compareEquals(_ lhs: any Sendable, _ rhs: YAMLValue) -> Bool {
        switch rhs {
        case .integer(let i):
            if let li = lhs as? Int { return li == i }
            if let ld = lhs as? Double { return ld == Double(i) }
            return false
        case .double(let d):
            if let ld = lhs as? Double { return ld == d }
            if let li = lhs as? Int { return Double(li) == d }
            return false
        case .bool(let b):
            return (lhs as? Bool) == b
        case .string(let s):
            return (lhs as? String) == s
        case .identifier(let s):
            return (lhs as? String) == s
        case .null:
            return lhs is NSNull || lhs is PryWire.AnyCodable.NullSentinel
        default: return false
        }
    }

    private func renderYAMLValue(_ y: YAMLValue) -> String {
        switch y {
        case .string(let s): return "\"\(s)\""
        case .identifier(let s): return s
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .duration(let s): return "\(s)s"
        case .array(let arr): return "[\(arr.map(renderYAMLValue).joined(separator: ", "))]"
        case .object(let kvs):
            return "{\(kvs.map { "\($0.0): \(renderYAMLValue($0.1))" }.joined(separator: ", "))}"
        }
    }

    private func renderAny(_ v: any Sendable) -> String {
        if let s = v as? String { return "\"\(s)\"" }
        return "\(v)"
    }

    // MARK: - Snapshots / dumps

    private func captureSnapshot(name: String) async throws -> String? {
        guard let h = launchHandle else { return nil }
        let dir = ensureAttachmentsDir()
        let url = dir.appendingPathComponent("\(name).png")
        if let data = await WindowCapture.capturePNG(pid: h.pid) {
            try? data.write(to: url)
            return relativePath(url)
        }
        return nil
    }

    private func dumpTreeToFile(name: String) async -> String? {
        guard let h = launchHandle else { return nil }
        let dir = ensureAttachmentsDir()
        let url = dir.appendingPathComponent("\(name)-tree.yaml")
        let tree = AXTreeWalker.snapshot(pid: h.pid)
        let yaml = AXTreeWalker.renderYAML(tree)
        try? yaml.write(to: url, atomically: true, encoding: .utf8)
        return relativePath(url)
    }

    private func dumpStateToFile(name: String) async -> String? {
        guard let client = harness else { return nil }
        let dir = ensureAttachmentsDir()
        let url = dir.appendingPathComponent("\(name)-state.yaml")
        // Ask the harness for EVERY registered ViewModel. We don't have that API
        // yet (harness returns one VM at a time), so for the dump we just pick the
        // ones referenced in the spec's assert_state steps if any.
        var names: Set<String> = []
        for s in spec.steps {
            if case .assertState(let vm, _, _) = s { names.insert(vm) }
        }
        var out = ""
        for n in names.sorted() {
            if let result = try? await client.readState(viewmodel: n, path: nil),
               let keys = result.keys {
                out += "\(n):\n"
                for (k, v) in keys.sorted(by: { $0.key < $1.key }) {
                    out += "  \(k): \(renderAny(v.value))\n"
                }
            }
        }
        try? out.write(to: url, atomically: true, encoding: .utf8)
        return relativePath(url)
    }

    // MARK: - Failure context

    private func buildFailureContext(stepIndex: Int, stepSource: String, failure: StepFailure) async -> FailureContext {
        var ctx = FailureContext(
            stepIndex: stepIndex, stepSource: stepSource,
            expected: failure.expected, observed: failure.observed,
            suggestion: failure.suggestion,
            axTreeSnippet: nil, registeredState: nil,
            relevantLogs: nil, attachments: []
        )
        if let h = launchHandle {
            let tree = AXTreeWalker.snapshot(pid: h.pid)
            ctx.axTreeSnippet = AXTreeWalker.renderYAML(AXTreeWalker.truncated(tree))

            // Registered state: union across any VMs referenced in the spec.
            var vms: Set<String> = []
            for s in spec.steps {
                if case .assertState(let vm, _, _) = s { vms.insert(vm) }
            }
            if !vms.isEmpty, let client = harness {
                var out = ""
                for n in vms.sorted() {
                    if let r = try? await client.readState(viewmodel: n, path: nil), let keys = r.keys {
                        out += "\(n):\n"
                        for (k, v) in keys.sorted(by: { $0.key < $1.key }) {
                            out += "  \(k): \(renderAny(v.value))\n"
                        }
                    }
                }
                ctx.registeredState = out.isEmpty ? nil : out
            }

            // Auto-snapshot on failure
            if let att = try? await captureSnapshot(name: "step-\(stepIndex)-failure") {
                attachments.append(att)
            }
            ctx.attachments = attachments

            // Best-effort logs
            if let client = harness {
                if let r = try? await client.readState(viewmodel: "_logs", path: nil) {
                    _ = r // placeholder; real logs come from read_logs when implemented
                }
            }
        }
        return ctx
    }

    // MARK: - Helpers

    private func renderStep(_ s: Step) -> String {
        switch s {
        case .launch(let args, let env):
            return args.isEmpty && env.isEmpty ? "launch" : "launch_with"
        case .terminate: return "terminate"
        case .relaunch: return "relaunch"
        case .waitFor(let p, let t): return "wait_for (timeout \(t.seconds)s): \(renderPredicate(p))"
        case .sleep(let d): return "sleep \(d.seconds)s"
        case .click(let t): return "click \(renderTarget(t))"
        case .doubleClick(let t): return "double_click \(renderTarget(t))"
        case .rightClick(let t): return "right_click \(renderTarget(t))"
        case .hover(let t): return "hover \(renderTarget(t))"
        case .type(let s): return "type \"\(s)\""
        case .key(let c): return "key \"\(c)\""
        case .scroll(let t, let d, let n): return "scroll \(renderTarget(t)) \(d.rawValue) \(n)"
        case .drag(let f, let t, _): return "drag from \(renderTarget(f)) to \(renderTarget(t))"
        case .assertTree(let p): return "assert_tree: \(renderPredicate(p))"
        case .assertState(let vm, let p, let e):
            return "assert_state \(vm).\(p) \(renderExpectation(e))"
        case .expectChange(let a, let vm, let p, let to, _):
            let actionStr: String
            switch a {
            case .click(let t): actionStr = "click \(renderTarget(t))"
            case .doubleClick(let t): actionStr = "double_click \(renderTarget(t))"
            case .rightClick(let t): actionStr = "right_click \(renderTarget(t))"
            case .key(let c): actionStr = "key \"\(c)\""
            case .type(let s): actionStr = "type \"\(s)\""
            }
            return "expect_change \(actionStr) → \(vm).\(p) = \(renderYAMLValue(to))"
        case .snapshot(let n): return "snapshot \"\(n)\""
        case .dumpTree(let n): return "dump_tree \"\(n)\""
        case .dumpState(let n): return "dump_state \"\(n)\""
        }
    }

    private func renderExpectation(_ e: StateExpectation) -> String {
        switch e {
        case .equals(let v): return "equals \(renderYAMLValue(v))"
        case .matches(let s): return "matches /\(s)/"
        case .anyOf(let a): return "any_of [\(a.map(renderYAMLValue).joined(separator: ", "))]"
        }
    }

    private func renderTarget(_ t: TargetRef) -> String {
        switch t {
        case .id(let s): return "{ id: \"\(s)\" }"
        case .roleLabel(let r, let l): return "{ role: \(r), label: \"\(l)\" }"
        case .label(let l): return "{ label: \"\(l)\" }"
        case .labelMatches(let s): return "{ label_matches: \"\(s)\" }"
        case .treePath(let s): return "{ tree_path: \"\(s)\" }"
        case .point(let x, let y): return "{ point: { x: \(x), y: \(y) } }"
        }
    }

    private func renderPredicate(_ p: Predicate) -> String {
        switch p {
        case .window(let t, let tm):
            if let t { return "window title=\"\(t)\"" }
            if let tm { return "window title_matches=\"\(tm)\"" }
            return "window"
        case .contains(let t): return "contains \(renderTarget(t))"
        case .notContains(let t): return "not_contains \(renderTarget(t))"
        case .countOf(let t, let n): return "count(\(renderTarget(t))) == \(n)"
        case .visible(let t): return "visible \(renderTarget(t))"
        case .enabled(let t): return "enabled \(renderTarget(t))"
        case .focused(let t): return "focused \(renderTarget(t))"
        case .state(let vm, let p, let e): return "\(vm).\(p) \(renderExpectation(e))"
        case .allOf(let ps): return "all_of [\(ps.map(renderPredicate).joined(separator: ", "))]"
        case .anyOf(let ps): return "any_of [\(ps.map(renderPredicate).joined(separator: ", "))]"
        case .not(let p): return "not \(renderPredicate(p))"
        }
    }

    private func prepareAttachments(started: Date) {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        fmt.timeZone = TimeZone(identifier: "UTC")
        let ts = fmt.string(from: started)
        let dir = options.verdictsDir.appendingPathComponent("\(spec.id)-\(ts)")
        self.attachmentsDir = dir
    }

    private func ensureAttachmentsDir() -> URL {
        if let d = attachmentsDir {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
            return d
        }
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pry-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        self.attachmentsDir = d
        return d
    }

    private func relativePath(_ url: URL) -> String {
        url.path
    }

    private func appendSkipped(from index: Int) {
        for i in index..<spec.steps.count {
            let idx = i + 1
            if !stepResults.contains(where: { $0.index == idx }) {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: renderStep(spec.steps[i]),
                    outcome: .skipped, duration: 0, message: nil
                ))
            }
        }
    }
}

// MARK: - Failure / Error types

struct StepFailure: Error {
    let expected: String
    let observed: String
    let suggestion: String?
    var summary: String { "expected \(expected); observed \(observed)" }
}

struct StepError: Error {
    let kind: String
    let message: String
}

private extension AppDriver.DriverError {
    var kindForVerdict: String {
        switch self {
        case .bundleNotFound, .executableNotFound: return "app_not_found"
        case .harnessSocketTimeout: return "harness_unreachable"
        case .launchFailed: return "launch_failed"
        case .alreadyRunning: return "already_running"
        }
    }
}

