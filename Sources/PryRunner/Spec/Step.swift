import Foundation

/// Parsed test spec step. One enum case per command in
/// `docs/design/spec-format.md §3`. Parameters are already parsed from the
/// YAML-flow source; the runner just executes.
public enum Step: Sendable {
    case launch(args: [String], env: [String: String])
    case terminate
    case relaunch

    case waitFor(predicate: Predicate, timeout: Duration)
    case sleep(Duration)

    case click(target: TargetRef, modifiers: [String])
    case doubleClick(target: TargetRef, modifiers: [String])
    case rightClick(target: TargetRef, modifiers: [String])
    case hover(target: TargetRef, dwellMs: Int?)
    case longPress(target: TargetRef, dwellMs: Int)
    case type(text: String, delayMs: Int?)
    /// Per-character typing — emits one CGEvent per character with a small
    /// inter-character gap. Use this when the target field filters on
    /// `key.count == 1` (typical SwiftUI .onKeyPress, IME-aware fields,
    /// search-as-you-type filters). Bulk `type:` would land as a single
    /// multi-char Unicode event that those handlers ignore silently.
    case typeChars(text: String, intervalMs: Int)
    case key(combo: String, repeatCount: Int)
    case scroll(target: TargetRef, direction: ScrollDirection, amount: Int)
    case drag(from: TargetRef, to: TargetRef, steps: Int, modifiers: [String])
    case marqueeDrag(from: PointSpec, to: PointSpec, modifiers: [String])
    case magnify(target: TargetRef, delta: Int)

    case assertTree(predicate: Predicate)
    case assertState(viewmodel: String, path: String, expect: StateExpectation)
    case assertFocus(target: TargetRef)
    case expectChange(action: ExpectChangeAction, viewmodel: String, path: String, to: YAMLValue, timeout: Duration)
    /// Like `assertState` but accumulates failures instead of bailing out.
    /// All soft failures are reported at the end of the spec.
    case softAssertState(viewmodel: String, path: String, expect: StateExpectation)
    /// Like `wait_for` but, on failure, the verdict frames it as an
    /// assertion (expected/observed) rather than a wait-timeout.
    case assertEventually(predicate: Predicate, timeout: Duration)

    case snapshot(name: String)
    case dumpTree(name: String)
    case dumpState(name: String)
    /// Append a "currently focused element" line to the verdict's diagnostic
    /// section. Replaces the empirical-`sleep:` workaround when chasing focus
    /// drift after sheet dismissal.
    case dumpFocus(name: String)
    /// Block until the named target acquires AX focus. Pair with `assert_focus`
    /// for definitive checks; this is the wait-form, more robust than `sleep:`.
    case waitForFocus(target: TargetRef, timeout: Duration)

    // Wave 1
    case clockAdvance(seconds: Double)
    case clockSet(iso8601: String, paused: Bool?)
    case setAnimations(enabled: Bool)
    case acceptSheet(button: String?)
    case dismissAlert
    case selectMenu(path: [String])
    case copy
    case paste
    case waitForIdle(timeout: Duration)
    case writePasteboard(text: String)
    case assertPasteboard(contains: String)
    // File panels (Open/Save dialogs)
    case openFile(path: String)
    case saveFile(path: String)
    case panelAccept(button: String?)
    case panelCancel

    // Wave 2 — control flow
    case `if`(predicate: Predicate, then: [Step], `else`: [Step])
    case forEach(varName: String, items: [YAMLValue], body: [Step])
    case repeatN(count: Int, body: [Step])
    case callFlow(name: String, args: [String: YAMLValue])
    /// Run `body`; on any failure, retry up to `count` more times with a
    /// short backoff between attempts.
    case withRetry(count: Int, body: [Step])

    // Selection helpers
    case selectRange(from: TargetRef, to: TargetRef)
    case multiSelect(targets: [TargetRef])

    // Capture pasteboard / VM state into a runtime variable for later use.
    case copyToVar(name: String, source: CaptureSource)
}

/// Source for `copy_to`. Captures the pasteboard or a single registered VM
/// state path into a runtime variable usable in subsequent steps as `${name}`.
public enum CaptureSource: Sendable {
    case pasteboard
    case state(viewmodel: String, path: String)
}

public enum StateExpectation: Sendable {
    case equals(YAMLValue)
    case notEquals(YAMLValue)
    case matches(String)
    case notMatches(String)
    case anyOf([YAMLValue])
    // Numeric comparators
    case gt(Double)
    case gte(Double)
    case lt(Double)
    case lte(Double)
    case between(low: Double, high: Double)
}

public enum ScrollDirection: String, Sendable {
    case up, down, left, right
}

/// Restricted action vocabulary for `expect_change`. We deliberately do not
/// allow arbitrary nested steps — composition lives in `wait_for` chained with
/// regular steps. expect_change is the atomic do-then-observe shortcut.
public indirect enum ExpectChangeAction: Sendable {
    case click(TargetRef)
    case doubleClick(TargetRef)
    case rightClick(TargetRef)
    case key(String)
    case type(String)
}

public indirect enum TargetRef: Sendable {
    case id(String)
    case roleLabel(role: String, label: String)
    case label(String)
    case labelMatches(String)
    case treePath(String)
    case point(x: Double, y: Double)
    /// Disambiguator: when the same target form would match multiple
    /// elements (e.g. SwiftUI propagates a container's `accessibilityIdentifier`
    /// to every descendant), `nth:` picks the n-th match in tree order.
    /// `expectedTotal` makes the selection self-checking — if the actual
    /// match count diverges from the expectation, the resolver fails loudly
    /// instead of silently picking a different element after an unrelated
    /// layout change.
    case nth(base: TargetRef, index: Int, expectedTotal: Int?)
}

public struct PointSpec: Sendable {
    public var x: Double
    public var y: Double
    public init(x: Double, y: Double) { self.x = x; self.y = y }
}

/// Tree / state predicate used by `wait_for` and `assert_tree`.
public indirect enum Predicate: Sendable {
    case contains(TargetRef)
    case notContains(TargetRef)
    case countOf(TargetRef, op: NumOp)
    case visible(TargetRef)
    case enabled(TargetRef)
    case focused(TargetRef)
    case state(viewmodel: String, path: String, expect: StateExpectation)
    case allOf([Predicate])
    case anyOf([Predicate])
    case not(Predicate)
    /// Window-existence shortcut: wait_for: { role: Window, title_matches: "..." }
    case window(title: String?, titleMatches: String?)
    /// Panel-shaped UI: NSOpenPanel/NSSavePanel can be sheets OR modal windows;
    /// this matches both forms.
    case panelOpen(titleMatches: String?)
    /// Sheet-shaped UI specifically (AXSheet child of any AXWindow).
    /// Distinct from `panelOpen` — file panels surface as either a sheet OR a
    /// modal window depending on `.begin` vs `.beginSheet`; many SwiftUI
    /// `.sheet(...)` modifiers always produce AXSheet.
    case sheetOpen(titleMatches: String?)
    /// Predicate must hold continuously for `seconds` (anti-flicker).
    /// Used by `assert_stable: PRED for: 1s`.
    case stableFor(Predicate, seconds: Double)
}

/// Integer comparison shared by tree counts and (later) other numeric predicates.
public enum NumOp: Sendable, Equatable {
    case eq(Int)
    case gt(Int)
    case gte(Int)
    case lt(Int)
    case lte(Int)
    case between(Int, Int)

    public func matches(_ n: Int) -> Bool {
        switch self {
        case .eq(let x): return n == x
        case .gt(let x): return n > x
        case .gte(let x): return n >= x
        case .lt(let x): return n < x
        case .lte(let x): return n <= x
        case .between(let a, let b): return n >= a && n <= b
        }
    }
}

/// Simple time budget used by `wait_for` and per-spec `timeout` frontmatter.
public struct Duration: Sendable, Equatable {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }

    public static let defaultWaitFor = Duration(seconds: 5)
    public static let defaultSpec = Duration(seconds: 60)
}
