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
    private var fixtureBaseURL: URL?
    private var defaultsSnapshot: DefaultsFixtures.Snapshot?

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

        // Fixtures (Wave 4): install BEFORE launch.
        if let fs = spec.withFS {
            do {
                fixtureBaseURL = try FilesystemFixtures.install(fs, specID: spec.id)
            } catch {
                let finished = Date()
                stepResults.append(StepResult(
                    index: 0, line: nil, source: "[fixture] with_fs",
                    outcome: .errored, duration: 0, message: "fixture install failed: \(error)"
                ))
                return Verdict(
                    specPath: spec.sourcePath, specID: spec.id, app: spec.app,
                    status: .errored, duration: finished.timeIntervalSince(started),
                    stepsTotal: 0, stepsPassed: 0, failedAtStep: nil,
                    startedAt: started, finishedAt: finished,
                    stepResults: stepResults, failure: nil,
                    errorKind: "fixture_failed", errorMessage: "\(error)",
                    attachmentsDir: attachmentsDir
                )
            }
        }
        if !spec.withDefaults.isEmpty {
            defaultsSnapshot = DefaultsFixtures.install(bundleID: spec.app, values: spec.withDefaults)
        }

        let globalDeadline = started.addingTimeInterval(spec.timeout.seconds)

        // Setup phase
        let setupResult = await runStepList(spec.setupSteps, label: "setup", baseIndex: 0, deadline: globalDeadline)
        var stepIndexOffset = spec.setupSteps.count
        if case .failed(let f) = setupResult {
            status = .failed
            failure = f
            // Still run teardown
        } else if case .errored(let kind, let msg) = setupResult {
            status = .errored
            errorKind = kind
            errorMessage = msg
        }

        // Apply spec-level animations setting (if launch happened in setup)
        if !spec.animationsEnabled, let h = harness, status == .passed {
            _ = try? await h.setAnimations(enabled: false)
        }

        // Start async handlers (Wave 1 — ADR-008)
        var handlerTask: Task<Void, Never>?
        if !spec.handlers.isEmpty, status == .passed {
            handlerTask = startHandlerLoop()
        }

        // Main phase (only if setup succeeded)
        if status == .passed {
            for (i, step) in spec.steps.enumerated() {
                if Date() > globalDeadline {
                    status = .timedOut
                    appendSkipped(from: stepIndexOffset + i)
                    break
                }
                let idx = stepIndexOffset + i + 1
                let stepStart = Date()
                let source = renderStep(step)
                do {
                    try await execute(step, stepIndex: idx, source: source)
                    stepResults.append(StepResult(
                        index: idx, line: nil, source: source,
                        outcome: .passed, duration: Date().timeIntervalSince(stepStart), message: nil
                    ))
                    // Per-step screenshot policy
                    if spec.screenshotsPolicy == .everyStep || spec.screenshotsPolicy == .always {
                        if let att = try? await captureSnapshot(name: "step-\(idx)") {
                            attachments.append(att)
                        }
                    }
                } catch let e as StepFailure {
                    stepResults.append(StepResult(
                        index: idx, line: nil, source: source,
                        outcome: .failed, duration: Date().timeIntervalSince(stepStart), message: e.summary
                    ))
                    status = .failed
                    failure = await buildFailureContext(stepIndex: idx, stepSource: source, failure: e)
                    appendSkippedMain(from: i + 1, indexOffset: stepIndexOffset)
                    break
                } catch let e as StepError {
                    stepResults.append(StepResult(
                        index: idx, line: nil, source: source,
                        outcome: .errored, duration: Date().timeIntervalSince(stepStart), message: e.message
                    ))
                    status = .errored
                    errorKind = e.kind
                    errorMessage = e.message
                    appendSkippedMain(from: i + 1, indexOffset: stepIndexOffset)
                    break
                } catch {
                    stepResults.append(StepResult(
                        index: idx, line: nil, source: source,
                        outcome: .errored, duration: Date().timeIntervalSince(stepStart), message: "\(error)"
                    ))
                    status = .errored
                    errorKind = "internal"
                    errorMessage = "\(error)"
                    appendSkippedMain(from: i + 1, indexOffset: stepIndexOffset)
                    break
                }
            }
        }

        stepIndexOffset += spec.steps.count

        // Teardown phase (always runs)
        handlerTask?.cancel()
        if let task = handlerTask { await task.value }
        _ = await runStepList(spec.teardownSteps, label: "teardown",
                              baseIndex: stepIndexOffset,
                              deadline: Date().addingTimeInterval(15))

        // Fixtures cleanup (always runs)
        if let snap = defaultsSnapshot { DefaultsFixtures.restore(snap) }
        if let url = fixtureBaseURL { FilesystemFixtures.cleanup(url) }

        let finished = Date()

        return Verdict(
            specPath: spec.sourcePath,
            specID: spec.id,
            app: spec.app,
            status: status,
            duration: finished.timeIntervalSince(started),
            stepsTotal: spec.setupSteps.count + spec.steps.count + spec.teardownSteps.count,
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

    // MARK: - Phase helpers (setup / teardown / handlers)

    private enum PhaseResult {
        case ok
        case failed(FailureContext)
        case errored(kind: String, message: String)
    }

    private func runStepList(_ steps: [Step], label: String, baseIndex: Int, deadline: Date) async -> PhaseResult {
        for (i, step) in steps.enumerated() {
            if Date() > deadline { return .errored(kind: "timed_out", message: "\(label) exceeded budget") }
            let idx = baseIndex + i + 1
            let stepStart = Date()
            let source = "[\(label)] " + renderStep(step)
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
                let ctx = await buildFailureContext(stepIndex: idx, stepSource: source, failure: e)
                return .failed(ctx)
            } catch let e as StepError {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: source,
                    outcome: .errored, duration: Date().timeIntervalSince(stepStart), message: e.message
                ))
                return .errored(kind: e.kind, message: e.message)
            } catch {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: source,
                    outcome: .errored, duration: Date().timeIntervalSince(stepStart), message: "\(error)"
                ))
                return .errored(kind: "internal", message: "\(error)")
            }
        }
        return .ok
    }

    private func appendSkippedMain(from index: Int, indexOffset: Int) {
        for i in index..<spec.steps.count {
            let idx = indexOffset + i + 1
            if !stepResults.contains(where: { $0.index == idx }) {
                stepResults.append(StepResult(
                    index: idx, line: nil, source: renderStep(spec.steps[i]),
                    outcome: .skipped, duration: 0, message: nil
                ))
            }
        }
    }

    /// Subscribe to harness notifications and dispatch matching handlers.
    private func startHandlerLoop() -> Task<Void, Never> {
        Task { [spec, weak self] in
            guard let self else { return }
            // Subscribe via the harness (Wave 1 wire surface).
            // Each notification is a JSON-RPC frame on the SAME socket — but
            // HarnessClient is request-response. For the spec runner we poll
            // a synthetic version: every 100ms, ask the harness for the
            // current registered names + state. If something changed since
            // last tick AND a handler matches, fire it.
            //
            // (Full push delivery requires a separate listener task on the
            // socket fd; that's tracked under ADR-008 for a future iteration.)
            var lastSnapshots: [String: [String: String]] = [:]
            var firedOnce: Set<String> = []

            while !Task.isCancelled {
                guard let harness = await self.harness else {
                    try? await Task.sleep(nanoseconds: 100_000_000); continue
                }
                for handler in spec.handlers {
                    if handler.mode == .once && firedOnce.contains(handler.name) { continue }
                    let triggered: Bool
                    switch handler.trigger {
                    case .stateChanged(let vm, let path):
                        let snap = (try? await harness.readState(viewmodel: vm, path: nil))?.keys ?? [:]
                        let stringified = snap.mapValues { "\($0.value)" }
                        let prev = lastSnapshots[vm] ?? [:]
                        var matched = false
                        for (k, v) in stringified where prev[k] != v {
                            if path == nil || k == path { matched = true; break }
                        }
                        lastSnapshots[vm] = stringified
                        triggered = matched
                    case .windowAppeared(let titleMatches), .sheetAppeared(let titleMatches):
                        // Walk AX tree, look for a window/sheet that wasn't there.
                        guard let h = await self.launchHandle else { triggered = false; break }
                        let tree = AXTreeWalker.snapshot(pid: h.pid)
                        var found = false
                        if case .windowAppeared = handler.trigger {
                            found = tree.children.contains(where: { n in
                                n.role == "AXWindow" && (titleMatches.map { Self.matchTitle(n.label, pattern: $0) } ?? true)
                            })
                        } else {
                            found = Self.treeContainsSheet(tree, titleMatches: titleMatches)
                        }
                        triggered = found && !firedOnce.contains(handler.name)
                    }

                    if triggered {
                        firedOnce.insert(handler.name)
                        for (idx, step) in handler.body.enumerated() {
                            do {
                                try await self.execute(step, stepIndex: -1000 - idx, source: "[handler:\(handler.name)] " + self.renderStep(step))
                            } catch {
                                // Swallow — handler errors don't fail the spec; they're advisory.
                                break
                            }
                        }
                        // Reset for `always` handlers
                        if handler.mode == .always { firedOnce.remove(handler.name) }
                    }
                }
                try? await Task.sleep(nanoseconds: 150_000_000)
            }
        }
    }

    nonisolated private static func matchTitle(_ title: String?, pattern: String) -> Bool {
        guard let t = title, let rx = try? NSRegularExpression(pattern: pattern) else { return false }
        return rx.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }

    nonisolated private static func treeContainsPanelOpen(_ node: AXNode, titleMatches: String?) -> Bool {
        // AXSheet — sheet attached to a parent window.
        if node.role == "AXSheet" {
            if let p = titleMatches { return Self.matchTitle(node.label, pattern: p) }
            return true
        }
        // Modal AXWindow with a panel-y title (NSOpenPanel/NSSavePanel surface
        // as separate windows when run via .begin instead of .beginSheet).
        if node.role == "AXWindow", let l = node.label?.lowercased(),
           l.contains("open") || l.contains("save") || l.contains("choose")
            || l.contains("import") || l.contains("export") {
            if let p = titleMatches { return Self.matchTitle(node.label, pattern: p) }
            return true
        }
        for c in node.children {
            if Self.treeContainsPanelOpen(c, titleMatches: titleMatches) { return true }
        }
        return false
    }

    private func collectAllIdentifiers(_ node: AXNode) -> [String] {
        var out: [String] = []
        func walk(_ n: AXNode) {
            if let id = n.identifier { out.append("\(n.role) #\(id)") }
            for c in n.children { walk(c) }
        }
        walk(node)
        return out
    }

    private func renderNumOp(_ op: NumOp) -> String {
        switch op {
        case .eq(let n): return "= \(n)"
        case .gt(let n): return "> \(n)"
        case .gte(let n): return ">= \(n)"
        case .lt(let n): return "< \(n)"
        case .lte(let n): return "<= \(n)"
        case .between(let a, let b): return "in [\(a), \(b)]"
        }
    }

    nonisolated private static func treeContainsSheet(_ node: AXNode, titleMatches: String?) -> Bool {
        if node.role == "AXSheet" {
            if let p = titleMatches { return Self.matchTitle(node.label, pattern: p) }
            return true
        }
        for c in node.children {
            if Self.treeContainsSheet(c, titleMatches: titleMatches) { return true }
        }
        return false
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

        case .click(let target, let mods):
            try await injectClick(target: target, kind: .single,
                                  modifiers: EventInjector.parseModifiers(mods),
                                  stepIndex: stepIndex, source: source)
        case .doubleClick(let target, let mods):
            try await injectClick(target: target, kind: .double,
                                  modifiers: EventInjector.parseModifiers(mods),
                                  stepIndex: stepIndex, source: source)
        case .rightClick(let target, let mods):
            try await injectClick(target: target, kind: .right,
                                  modifiers: EventInjector.parseModifiers(mods),
                                  stepIndex: stepIndex, source: source)
        case .hover(let target, let dwellMs):
            try ElementResolver.requireTrust()
            let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "hover target has frame", observed: "\(r.role) no frame", suggestion: nil)
            }
            let p = CGPoint(x: f.midX, y: f.midY)
            if let d = dwellMs {
                try EventInjector.hoverDwell(at: p, dwellMs: d)
            } else {
                try EventInjector.move(to: p)
            }
        case .longPress(let target, let dwellMs):
            try ElementResolver.requireTrust()
            let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "long_press target has frame", observed: "\(r.role) no frame", suggestion: nil)
            }
            try EventInjector.longPress(at: CGPoint(x: f.midX, y: f.midY), dwellMs: dwellMs)

        case .type(let text, let delayMs):
            try ElementResolver.requireTrust()
            if let d = delayMs {
                try EventInjector.typeWithDelay(text: text, intervalMs: d)
            } else {
                try EventInjector.type(text: text)
            }

        case .key(let combo, let n):
            try ElementResolver.requireTrust()
            if n > 1 { try EventInjector.keyRepeat(combo: combo, count: n) }
            else { try EventInjector.key(combo: combo) }

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

        case .drag(let from, let to, let steps, let mods):
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
            let f = EventInjector.parseModifiers(mods)
            if !f.isEmpty {
                // For a drag with modifiers we wrap it: hold modifiers via key-down before drag.
                // The CGEventFlags on mouse events is simpler — set on each event.
                // EventInjector.drag uses default-flag mouse events; we create a custom flow.
                try dragWithModifiers(from: fromP, to: toP, steps: steps, flags: f)
            } else {
                try EventInjector.drag(from: fromP, to: toP, steps: steps)
            }

        case .marqueeDrag(let fromP, let toP, let mods):
            try ElementResolver.requireTrust()
            let f = EventInjector.parseModifiers(mods)
            if !f.isEmpty {
                try dragWithModifiers(from: CGPoint(x: fromP.x, y: fromP.y),
                                      to: CGPoint(x: toP.x, y: toP.y), steps: 12, flags: f)
            } else {
                try EventInjector.drag(from: CGPoint(x: fromP.x, y: fromP.y),
                                       to: CGPoint(x: toP.x, y: toP.y), steps: 12)
            }

        case .magnify(let target, let delta):
            try ElementResolver.requireTrust()
            let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
            guard let f = r.frame else {
                throw StepFailure(expected: "magnify target has frame", observed: "\(r.role) no frame", suggestion: nil)
            }
            try EventInjector.magnify(at: CGPoint(x: f.midX, y: f.midY), delta: Int32(delta))

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

        // Wave 1
        case .clockAdvance(let seconds):
            guard let h = harness else { throw StepError(kind: "not_launched", message: "no running app") }
            _ = try await h.clockAdvance(seconds: seconds)

        case .clockSet(let iso, let paused):
            guard let h = harness else { throw StepError(kind: "not_launched", message: "no running app") }
            _ = try await h.clockSet(iso8601: iso, paused: paused)

        case .setAnimations(let enabled):
            guard let h = harness else { throw StepError(kind: "not_launched", message: "no running app") }
            _ = try await h.setAnimations(enabled: enabled)

        case .acceptSheet(let buttonName):
            // Heuristic: find a sheet on any window of the target, then click the
            // requested button (or the default "OK"/"Save"/"Done").
            try ElementResolver.requireTrust()
            try await acceptSheet(buttonName: buttonName, stepIndex: stepIndex, source: source)

        case .dismissAlert:
            try ElementResolver.requireTrust()
            try EventInjector.key(combo: "esc")

        case .selectMenu(let path):
            try ElementResolver.requireTrust()
            try await selectMenuPath(path, stepIndex: stepIndex, source: source)

        case .copy:
            try ElementResolver.requireTrust()
            try EventInjector.key(combo: "cmd+c")

        case .paste:
            try ElementResolver.requireTrust()
            try EventInjector.key(combo: "cmd+v")

        case .waitForIdle(let timeout):
            try await waitForIdle(timeout: timeout)

        case .writePasteboard(let text):
            guard let h = harness else { throw StepError(kind: "not_launched", message: "no running app") }
            _ = try await h.writePasteboard(string: text)

        case .assertPasteboard(let needle):
            guard let h = harness else { throw StepError(kind: "not_launched", message: "no running app") }
            let r = try await h.readPasteboard()
            guard let s = r.string, s.contains(needle) else {
                throw StepFailure(
                    expected: "pasteboard contains \"\(needle)\"",
                    observed: "got \"\(r.string ?? "<empty>")\"",
                    suggestion: nil
                )
            }

        case .openFile(let path):
            try ElementResolver.requireTrust()
            try await openFileInPanel(path: path, stepIndex: stepIndex, source: source)

        case .saveFile(let path):
            try ElementResolver.requireTrust()
            try await saveFileInPanel(path: path, stepIndex: stepIndex, source: source)

        case .panelAccept(let button):
            try ElementResolver.requireTrust()
            try await acceptOpenOrSavePanel(button: button)

        case .panelCancel:
            try ElementResolver.requireTrust()
            try EventInjector.key(combo: "esc")

        // Wave 2 control flow
        case .if(let pred, let thenSteps, let elseSteps):
            do {
                try await evaluatePredicate(pred)
                for (idx, s) in thenSteps.enumerated() {
                    try await execute(s, stepIndex: stepIndex * 1000 + idx, source: renderStep(s))
                }
            } catch is PredicateFailure {
                for (idx, s) in elseSteps.enumerated() {
                    try await execute(s, stepIndex: stepIndex * 1000 + idx, source: renderStep(s))
                }
            }

        case .forEach(let varName, let items, let body):
            for (idx, item) in items.enumerated() {
                let interpolated = body.map { interpolateStep($0, vars: [varName: item]) }
                for (j, s) in interpolated.enumerated() {
                    try await execute(s, stepIndex: stepIndex * 10000 + idx * 100 + j, source: renderStep(s))
                }
            }

        case .repeatN(let count, let body):
            for i in 0..<count {
                for (j, s) in body.enumerated() {
                    try await execute(s, stepIndex: stepIndex * 10000 + i * 100 + j, source: renderStep(s))
                }
            }

        case .callFlow(let name, let args):
            guard let flow = spec.flows[name] else {
                throw StepError(kind: "unknown_flow", message: "no flow named '\(name)' (declared flows: \(spec.flows.keys.sorted()))")
            }
            let interpolated = flow.body.map { interpolateStep($0, vars: args) }
            for (j, s) in interpolated.enumerated() {
                try await execute(s, stepIndex: stepIndex * 10000 + j, source: renderStep(s))
            }
        }
    }

    // MARK: - Wave 1 helpers

    /// Find a sheet on any window and click the named button (or the default).
    private func acceptSheet(buttonName: String?, stepIndex: Int, source: String) async throws {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        let tree = AXTreeWalker.snapshot(pid: h.pid)
        let candidates = collectSheetButtons(in: tree)
        guard !candidates.isEmpty else {
            throw StepFailure(
                expected: "an open sheet with at least one button",
                observed: "no AXSheet found in any window",
                suggestion: "If your sheet uses NSAlert, try `dismiss_alert` instead."
            )
        }
        let want = buttonName?.lowercased()
        let pick: AXNode
        if let want {
            guard let m = candidates.first(where: { $0.label?.lowercased() == want }) else {
                throw StepFailure(
                    expected: "sheet button labelled '\(buttonName!)'",
                    observed: "available: \(candidates.compactMap(\.label).joined(separator: ", "))",
                    suggestion: nil
                )
            }
            pick = m
        } else {
            // Default order of preference for "accept": OK, Save, Done, Continue, Allow.
            let preferred = ["ok", "save", "done", "continue", "allow", "yes"]
            pick = candidates.first(where: { n in
                guard let l = n.label?.lowercased() else { return false }
                return preferred.contains(l)
            }) ?? candidates[0]
        }
        guard let f = pick.frame, f.count == 4 else {
            throw StepFailure(expected: "sheet button has a frame", observed: "no frame on \(pick.label ?? "?")", suggestion: nil)
        }
        try EventInjector.click(at: CGPoint(x: f[0] + f[2] / 2, y: f[1] + f[3] / 2))
    }

    private func collectSheetButtons(in node: AXNode) -> [AXNode] {
        var out: [AXNode] = []
        func walk(_ n: AXNode, insideSheet: Bool) {
            let nowInside = insideSheet || n.role == "AXSheet"
            if nowInside, n.role == "AXButton" { out.append(n) }
            for c in n.children { walk(c, insideSheet: nowInside) }
        }
        walk(node, insideSheet: false)
        return out
    }

    // MARK: - File panels (Open / Save dialogs)

    /// Drive an open-style NSOpenPanel: cmd+shift+g to surface "Go to folder",
    /// type the absolute path, accept. Works against either sheet-attached
    /// panels or modal-window panels.
    private func openFileInPanel(path: String, stepIndex: Int, source: String) async throws {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        try await waitForPanelReady(pid: h.pid, timeout: 2)
        // "Go to folder" sheet inside the panel.
        try EventInjector.key(combo: "shift+cmd+g")
        try? await Task.sleep(nanoseconds: 250_000_000)
        try EventInjector.type(text: path)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try EventInjector.key(combo: "return")             // accept Go-to-folder
        try? await Task.sleep(nanoseconds: 250_000_000)
        // Either Return again accepts Open, or we click the default button explicitly.
        try await acceptOpenOrSavePanel(button: nil)
    }

    /// Drive a save-style NSSavePanel: navigate to the directory, fill the
    /// name field, click Save.
    private func saveFileInPanel(path: String, stepIndex: Int, source: String) async throws {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        try await waitForPanelReady(pid: h.pid, timeout: 2)
        let url = URL(fileURLWithPath: path)
        let dir = url.deletingLastPathComponent().path
        let name = url.lastPathComponent

        // Navigate to target directory via Cmd+Shift+G.
        try EventInjector.key(combo: "shift+cmd+g")
        try? await Task.sleep(nanoseconds: 250_000_000)
        try EventInjector.type(text: dir)
        try? await Task.sleep(nanoseconds: 100_000_000)
        try EventInjector.key(combo: "return")
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Focus the name field. NSSavePanel's name field has its title set to
        // "Save As:" — focus by clicking it. Fallback: assume it's already focused.
        if let nameField = findSavePanelNameField(in: AXTreeWalker.snapshot(pid: h.pid)),
           let f = nameField.frame, f.count == 4 {
            try EventInjector.click(at: CGPoint(x: f[0] + f[2] / 2, y: f[1] + f[3] / 2))
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        // Select-all + delete clears any previous filename.
        try EventInjector.key(combo: "cmd+a")
        try EventInjector.key(combo: "delete")
        try EventInjector.type(text: name)
        try? await Task.sleep(nanoseconds: 150_000_000)
        try await acceptOpenOrSavePanel(button: nil)
    }

    /// Click the default accept button on whatever panel is open.
    /// Recognizes AXSheet (sheet-attached) and AXWindow with subrole AXDialog
    /// (separate-window panel). Falls back to pressing Return if no button is
    /// found — many panels accept Return as the default action anyway.
    private func acceptOpenOrSavePanel(button: String?) async throws {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        let tree = AXTreeWalker.snapshot(pid: h.pid)
        let candidates = collectPanelButtons(in: tree)
        if candidates.isEmpty {
            // Cleanest fallback for an Open/Save panel — Return is the default action.
            try EventInjector.key(combo: "return")
            return
        }
        let want = button?.lowercased()
        let pick: AXNode
        if let want {
            guard let m = candidates.first(where: { $0.label?.lowercased() == want }) else {
                throw StepFailure(
                    expected: "panel button labelled '\(button!)'",
                    observed: "available: \(candidates.compactMap(\.label).joined(separator: ", "))",
                    suggestion: nil
                )
            }
            pick = m
        } else {
            let preferred = ["open", "save", "choose", "ok", "done", "import", "export"]
            pick = candidates.first(where: { n in
                guard let l = n.label?.lowercased() else { return false }
                return preferred.contains(l)
            }) ?? candidates[0]
        }
        guard let f = pick.frame, f.count == 4 else {
            try EventInjector.key(combo: "return")
            return
        }
        try EventInjector.click(at: CGPoint(x: f[0] + f[2] / 2, y: f[1] + f[3] / 2))
    }

    /// Wait until a sheet OR a dialog-subrole window appears under the target.
    private func waitForPanelReady(pid: pid_t, timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let tree = AXTreeWalker.snapshot(pid: pid)
            if Self.treeContainsPanel(tree) { return }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        // Don't fail hard — sometimes the panel was already up before the step.
        // The follow-up keystrokes are the actual test.
    }

    nonisolated private static func treeContainsPanel(_ node: AXNode) -> Bool {
        if node.role == "AXSheet" { return true }
        if node.role == "AXWindow", let l = node.label,
           l.lowercased().contains("open") || l.lowercased().contains("save") || l.lowercased().contains("choose") || l.lowercased().contains("import") || l.lowercased().contains("export") {
            return true
        }
        for c in node.children {
            if Self.treeContainsPanel(c) { return true }
        }
        return false
    }

    /// Collect candidate buttons inside any panel (sheet, dialog window).
    private func collectPanelButtons(in node: AXNode) -> [AXNode] {
        var out: [AXNode] = []
        func walk(_ n: AXNode, insidePanel: Bool) {
            let here = insidePanel
                || n.role == "AXSheet"
                || (n.role == "AXWindow" && (n.label?.lowercased().contains("open") == true
                                              || n.label?.lowercased().contains("save") == true
                                              || n.label?.lowercased().contains("choose") == true
                                              || n.label?.lowercased().contains("import") == true
                                              || n.label?.lowercased().contains("export") == true))
            if here, n.role == "AXButton" { out.append(n) }
            for c in n.children { walk(c, insidePanel: here) }
        }
        walk(node, insidePanel: false)
        return out
    }

    /// Find the "Save As:" name field in an NSSavePanel.
    private func findSavePanelNameField(in node: AXNode) -> AXNode? {
        if node.role == "AXTextField",
           let v = node.value, // generally empty unless user already typed
           v.isEmpty || v.contains(".") { return node }
        // Heuristic: any AXTextField inside a panel-shaped subtree.
        if node.role == "AXSheet" || node.role == "AXWindow" {
            // Prefer the first AXTextField at this level.
            for c in node.children {
                if c.role == "AXTextField" { return c }
                if let found = findSavePanelNameField(in: c) { return found }
            }
        }
        for c in node.children {
            if let found = findSavePanelNameField(in: c) { return found }
        }
        return nil
    }

    private func selectMenuPath(_ path: [String], stepIndex: Int, source: String) async throws {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        guard !path.isEmpty else {
            throw StepFailure(expected: "menu path with at least one segment", observed: "empty path", suggestion: nil)
        }
        // For menu navigation we use AX `Press` actions directly — clicking menu
        // bar items by frame is fragile because menu items aren't on screen
        // until their parent is opened. AX `Press` opens the menu, then we
        // recursively press children.
        let app = AXUIElementCreateApplication(h.pid)
        guard let menuBarRef = axAttr(app, kAXMenuBarAttribute) else {
            throw StepFailure(expected: "AXMenuBar present", observed: "no menu bar", suggestion: nil)
        }
        let menuBar = menuBarRef as! AXUIElement
        var current: AXUIElement = menuBar
        for (i, segment) in path.enumerated() {
            guard let children = axAttr(current, kAXChildrenAttribute) as? [AXUIElement] else {
                throw StepFailure(
                    expected: "menu '\(path[0..<i].joined(separator: " > "))' has children",
                    observed: "no children", suggestion: nil)
            }
            guard let next = children.first(where: { (axAttr($0, kAXTitleAttribute) as? String) == segment }) else {
                let titles = children.compactMap { axAttr($0, kAXTitleAttribute) as? String }
                throw StepFailure(
                    expected: "menu segment '\(segment)' under '\(path.prefix(i).joined(separator: " > "))'",
                    observed: "available: \(titles.joined(separator: ", "))",
                    suggestion: nil)
                }
            // Press to open submenu (or activate leaf)
            AXUIElementPerformAction(next, kAXPressAction as CFString)
            current = next
            // For a leaf (last segment), Press is the activation; we're done.
            if i < path.count - 1 {
                // For non-leaves on macOS, the children appear under an AXMenu child of `next`.
                // Walk into the AXMenu role to find subsequent items.
                if let kids = axAttr(next, kAXChildrenAttribute) as? [AXUIElement],
                   let menu = kids.first(where: { (axAttr($0, kAXRoleAttribute) as? String) == "AXMenu" }) {
                    current = menu
                }
                try? await Task.sleep(nanoseconds: 60_000_000)
            }
        }
    }

    private func axAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        return err == .success ? value : nil
    }

    /// Wait until no AX events fire for a quiescence interval. Best-effort: we
    /// simply diff the AX tree at intervals and return when it's stable.
    private func waitForIdle(timeout: Duration) async throws {
        guard let h = launchHandle else {
            throw StepError(kind: "not_launched", message: "no running app")
        }
        let deadline = Date().addingTimeInterval(timeout.seconds)
        var lastSize = -1
        var stableSince: Date?
        while Date() < deadline {
            let tree = AXTreeWalker.snapshot(pid: h.pid)
            let size = countNodes(tree)
            if size == lastSize {
                if stableSince == nil { stableSince = Date() }
                else if Date().timeIntervalSince(stableSince!) > 0.25 { return }
            } else {
                stableSince = nil
                lastSize = size
            }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        // Timeout — not a failure, just return. The semantic is "best effort".
    }

    private func countNodes(_ n: AXNode) -> Int {
        var c = 1
        for k in n.children { c += countNodes(k) }
        return c
    }

    // MARK: - Variable substitution (Wave 2)

    /// Recursively replace `${name}` strings in a Step's parameters using the
    /// provided variable bindings. Only string-bearing fields are touched.
    private func interpolateStep(_ step: Step, vars: [String: YAMLValue]) -> Step {
        switch step {
        case .click(let t, let m): return .click(target: interpolateTarget(t, vars: vars), modifiers: m)
        case .doubleClick(let t, let m): return .doubleClick(target: interpolateTarget(t, vars: vars), modifiers: m)
        case .rightClick(let t, let m): return .rightClick(target: interpolateTarget(t, vars: vars), modifiers: m)
        case .hover(let t, let d): return .hover(target: interpolateTarget(t, vars: vars), dwellMs: d)
        case .longPress(let t, let d): return .longPress(target: interpolateTarget(t, vars: vars), dwellMs: d)
        case .type(let s, let d): return .type(text: interpolateString(s, vars: vars), delayMs: d)
        case .key(let s, let n): return .key(combo: interpolateString(s, vars: vars), repeatCount: n)
        case .selectMenu(let path):
            return .selectMenu(path: path.map { interpolateString($0, vars: vars) })
        case .writePasteboard(let s): return .writePasteboard(text: interpolateString(s, vars: vars))
        case .assertPasteboard(let s): return .assertPasteboard(contains: interpolateString(s, vars: vars))
        default: return step
        }
    }

    private func interpolateTarget(_ t: TargetRef, vars: [String: YAMLValue]) -> TargetRef {
        switch t {
        case .id(let s): return .id(interpolateString(s, vars: vars))
        case .label(let s): return .label(interpolateString(s, vars: vars))
        case .labelMatches(let s): return .labelMatches(interpolateString(s, vars: vars))
        case .roleLabel(let r, let l): return .roleLabel(role: r, label: interpolateString(l, vars: vars))
        case .treePath(let s): return .treePath(interpolateString(s, vars: vars))
        case .point: return t
        case .nth(let base, let i): return .nth(base: interpolateTarget(base, vars: vars), index: i)
        }
    }

    private func interpolateString(_ s: String, vars: [String: YAMLValue]) -> String {
        var out = s
        for (k, v) in vars {
            let needle = "${\(k)}"
            let replacement: String
            switch v {
            case .string(let x): replacement = x
            case .identifier(let x): replacement = x
            case .integer(let x): replacement = String(x)
            case .double(let x): replacement = String(x)
            case .bool(let x): replacement = String(x)
            default: replacement = "\(v)"
            }
            out = out.replacingOccurrences(of: needle, with: replacement)
        }
        return out
    }

    // MARK: - Launch

    private func doLaunch(args: [String], env: [String: String]) async throws {
        do {
            let handle: AppDriver.Handle
            // Resolution order for executablePath:
            //  1. Explicit `executable_path:` in spec frontmatter
            //  2. `.pry/config.yaml` apps[<bundle-id>].executable_path (or env override)
            //  3. NSWorkspace lookup by bundle ID
            let resolvedExec: String? = spec.executablePath ?? { () -> String? in
                guard let sourcePath = spec.sourcePath else { return nil }
                let cfg = PryConfig.discover(from: URL(fileURLWithPath: sourcePath))
                return cfg?.resolveExecutablePath(for: spec.app)
            }()
            if let path = resolvedExec {
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

    private func injectClick(target: TargetRef, kind: ClickKind,
                             modifiers: CGEventFlags = [],
                             stepIndex: Int, source: String) async throws {
        try ElementResolver.requireTrust()
        let r = try resolveTarget(target, stepSource: source, stepIndex: stepIndex)
        guard let f = r.frame else {
            throw StepFailure(expected: "target resolves to an element with a frame",
                              observed: "\(r.role) has no frame",
                              suggestion: nil)
        }
        let p = CGPoint(x: f.midX, y: f.midY)
        switch kind {
        case .single: try EventInjector.click(at: p, modifiers: modifiers)
        case .double: try EventInjector.doubleClick(at: p, modifiers: modifiers)
        case .right: try EventInjector.rightClick(at: p, modifiers: modifiers)
        }
    }

    /// Drag while holding modifier flags. Each constituent CGEvent carries the flags.
    private func dragWithModifiers(from: CGPoint, to: CGPoint, steps: Int, flags: CGEventFlags) throws {
        let src = CGEventSource(stateID: .hidSystemState)
        if let d = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown,
                           mouseCursorPosition: from, mouseButton: .left) {
            d.flags = flags
            d.post(tap: .cgSessionEventTap)
        }
        usleep(12_000)
        let n = max(1, steps)
        for i in 1...n {
            let t = Double(i) / Double(n)
            let p = CGPoint(x: from.x + (to.x - from.x) * t,
                            y: from.y + (to.y - from.y) * t)
            if let m = CGEvent(mouseEventSource: src, mouseType: .leftMouseDragged,
                               mouseCursorPosition: p, mouseButton: .left) {
                m.flags = flags
                m.post(tap: .cgSessionEventTap)
            }
            usleep(12_000)
        }
        if let u = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,
                           mouseCursorPosition: to, mouseButton: .left) {
            u.flags = flags
            u.post(tap: .cgSessionEventTap)
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
        case .nth(let base, let i): return .nth(base: convert(base), index: i)
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

        case .countOf(let target, let op):
            let count = countMatches(target)
            if !op.matches(count) {
                throw PredicateFailure(description: "count(\(target)) = \(count), expected \(renderNumOp(op))")
            }

        case .panelOpen(let titleMatches):
            guard let h = launchHandle else { throw PredicateFailure(description: "no running app") }
            let tree = AXTreeWalker.snapshot(pid: h.pid)
            let found = Self.treeContainsPanelOpen(tree, titleMatches: titleMatches)
            if !found {
                throw PredicateFailure(description: "no open NSOpenPanel/NSSavePanel/AXSheet found")
            }

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
        case .nth(let base, _):
            // Count semantics treat nth as base — we want "how many match the
            // base form", not "is this exactly the nth".
            return nodeMatches(node, base)
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
            // Auto-coerce numerics to their string form so `matches: "^[0-9]+$"`
            // works against an Int/Double field without forcing the host VM
            // to expose a String wrapper.
            let str = stringForMatch(value)
            guard let s = str, let rx = try? NSRegularExpression(pattern: pattern) else {
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
        case .gt(let n):
            guard let v = doubleValue(value) else {
                throw StepFailure(expected: "numeric value > \(n)", observed: renderAny(value), suggestion: nil)
            }
            if !(v > n) {
                throw StepFailure(expected: "\(viewmodel).\(path) > \(n)",
                                  observed: "got \(v)", suggestion: nil)
            }
        case .gte(let n):
            guard let v = doubleValue(value) else {
                throw StepFailure(expected: "numeric value >= \(n)", observed: renderAny(value), suggestion: nil)
            }
            if !(v >= n) {
                throw StepFailure(expected: "\(viewmodel).\(path) >= \(n)",
                                  observed: "got \(v)", suggestion: nil)
            }
        case .lt(let n):
            guard let v = doubleValue(value) else {
                throw StepFailure(expected: "numeric value < \(n)", observed: renderAny(value), suggestion: nil)
            }
            if !(v < n) {
                throw StepFailure(expected: "\(viewmodel).\(path) < \(n)",
                                  observed: "got \(v)", suggestion: nil)
            }
        case .lte(let n):
            guard let v = doubleValue(value) else {
                throw StepFailure(expected: "numeric value <= \(n)", observed: renderAny(value), suggestion: nil)
            }
            if !(v <= n) {
                throw StepFailure(expected: "\(viewmodel).\(path) <= \(n)",
                                  observed: "got \(v)", suggestion: nil)
            }
        case .between(let lo, let hi):
            guard let v = doubleValue(value) else {
                throw StepFailure(expected: "numeric value in [\(lo), \(hi)]",
                                  observed: renderAny(value), suggestion: nil)
            }
            if !(v >= lo && v <= hi) {
                throw StepFailure(expected: "\(viewmodel).\(path) in [\(lo), \(hi)]",
                                  observed: "got \(v)", suggestion: nil)
            }
        }
    }

    private func doubleValue(_ v: any Sendable) -> Double? {
        if let i = v as? Int { return Double(i) }
        if let d = v as? Double { return d }
        if let f = v as? Float { return Double(f) }
        if let n = v as? NSNumber { return n.doubleValue }
        if let s = v as? String { return Double(s) }
        return nil
    }

    private func stringForMatch(_ v: any Sendable) -> String? {
        if let s = v as? String { return s }
        if let i = v as? Int { return String(i) }
        if let d = v as? Double { return String(d) }
        if let f = v as? Float { return String(f) }
        if let b = v as? Bool { return String(b) }
        if let n = v as? NSNumber { return n.stringValue }
        return nil
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
            // Truncated tree first; if that comes out empty (rare — e.g. AX query
            // failed transiently), fall back to a list of registered IDs so the
            // verdict isn't silently empty.
            let truncated = AXTreeWalker.renderYAML(AXTreeWalker.truncated(tree))
            if truncated.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ids = collectAllIdentifiers(tree)
                ctx.axTreeSnippet = ids.isEmpty
                    ? "(AX tree returned empty; check that the app is still running)"
                    : "Registered AXIdentifiers in the tree:\n  - " + ids.joined(separator: "\n  - ")
            } else {
                ctx.axTreeSnippet = truncated
            }

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
        case .click(let t, let m): return "click \(renderTarget(t))\(modSuffix(m))"
        case .doubleClick(let t, let m): return "double_click \(renderTarget(t))\(modSuffix(m))"
        case .rightClick(let t, let m): return "right_click \(renderTarget(t))\(modSuffix(m))"
        case .hover(let t, _): return "hover \(renderTarget(t))"
        case .longPress(let t, let d): return "long_press \(renderTarget(t)) (\(d)ms)"
        case .type(let s, _): return "type \"\(s)\""
        case .key(let c, let n): return n > 1 ? "key \"\(c)\" ×\(n)" : "key \"\(c)\""
        case .scroll(let t, let d, let n): return "scroll \(renderTarget(t)) \(d.rawValue) \(n)"
        case .drag(let f, let t, _, let m): return "drag from \(renderTarget(f)) to \(renderTarget(t))\(modSuffix(m))"
        case .marqueeDrag(let f, let t, let m): return "marquee from (\(f.x),\(f.y)) to (\(t.x),\(t.y))\(modSuffix(m))"
        case .magnify(let t, let d): return "magnify \(renderTarget(t)) \(d > 0 ? "+" : "")\(d)"
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

        // Wave 1
        case .clockAdvance(let s): return "clock.advance \(s)s"
        case .clockSet(let iso, let p): return "clock.set \(iso)\(p == true ? " paused" : "")"
        case .setAnimations(let on): return "set_animations \(on ? "on" : "off")"
        case .acceptSheet(let b): return "accept_sheet\(b.map { " \"\($0)\"" } ?? "")"
        case .dismissAlert: return "dismiss_alert"
        case .selectMenu(let path): return "select_menu \"\(path.joined(separator: " > "))\""
        case .copy: return "copy"
        case .paste: return "paste"
        case .waitForIdle(let t): return "wait_for_idle \(t.seconds)s"
        case .writePasteboard(let s): return "write_pasteboard \"\(s)\""
        case .assertPasteboard(let s): return "assert_pasteboard contains \"\(s)\""
        case .openFile(let p): return "open_file \"\(p)\""
        case .saveFile(let p): return "save_file \"\(p)\""
        case .panelAccept(let b): return "panel_accept\(b.map { " \"\($0)\"" } ?? "")"
        case .panelCancel: return "panel_cancel"

        // Wave 2
        case .if(let p, _, _): return "if \(renderPredicate(p))"
        case .forEach(let v, let items, _): return "for \(v) in [\(items.count) items]"
        case .repeatN(let n, _): return "repeat \(n) times"
        case .callFlow(let name, _): return "call \(name)"
        }
    }

    private func modSuffix(_ mods: [String]) -> String {
        mods.isEmpty ? "" : " [\(mods.joined(separator: "+"))]"
    }

    private func renderExpectation(_ e: StateExpectation) -> String {
        switch e {
        case .equals(let v): return "equals \(renderYAMLValue(v))"
        case .matches(let s): return "matches /\(s)/"
        case .anyOf(let a): return "any_of [\(a.map(renderYAMLValue).joined(separator: ", "))]"
        case .gt(let n): return "> \(n)"
        case .gte(let n): return ">= \(n)"
        case .lt(let n): return "< \(n)"
        case .lte(let n): return "<= \(n)"
        case .between(let lo, let hi): return "between [\(lo), \(hi)]"
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
        case .nth(let base, let i): return "\(renderTarget(base))[nth=\(i)]"
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
        case .countOf(let t, let op): return "count(\(renderTarget(t))) \(renderNumOp(op))"
        case .visible(let t): return "visible \(renderTarget(t))"
        case .enabled(let t): return "enabled \(renderTarget(t))"
        case .focused(let t): return "focused \(renderTarget(t))"
        case .state(let vm, let p, let e): return "\(vm).\(p) \(renderExpectation(e))"
        case .allOf(let ps): return "all_of [\(ps.map(renderPredicate).joined(separator: ", "))]"
        case .anyOf(let ps): return "any_of [\(ps.map(renderPredicate).joined(separator: ", "))]"
        case .not(let p): return "not \(renderPredicate(p))"
        case .panelOpen(let tm):
            return "panel_open\(tm.map { " title_matches=\"\($0)\"" } ?? "")"
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
            seedGitignore(at: d.deletingLastPathComponent())
            return d
        }
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("pry-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        self.attachmentsDir = d
        return d
    }

    /// Drop a `.gitignore` next to the verdicts root so attachments don't leak
    /// into a project's git history. Idempotent — only writes if absent.
    private nonisolated func seedGitignore(at verdictsRoot: URL) {
        let gi = verdictsRoot.appendingPathComponent(".gitignore")
        guard !FileManager.default.fileExists(atPath: gi.path) else { return }
        let body = "# Auto-generated by Pry — verdicts are run artifacts.\n*\n!.gitignore\n"
        try? body.write(to: gi, atomically: true, encoding: .utf8)
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

