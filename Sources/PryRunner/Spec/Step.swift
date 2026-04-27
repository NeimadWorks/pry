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
    case key(combo: String, repeatCount: Int)
    case scroll(target: TargetRef, direction: ScrollDirection, amount: Int)
    case drag(from: TargetRef, to: TargetRef, steps: Int, modifiers: [String])
    case marqueeDrag(from: PointSpec, to: PointSpec, modifiers: [String])
    case magnify(target: TargetRef, delta: Int)

    case assertTree(predicate: Predicate)
    case assertState(viewmodel: String, path: String, expect: StateExpectation)
    case expectChange(action: ExpectChangeAction, viewmodel: String, path: String, to: YAMLValue, timeout: Duration)

    case snapshot(name: String)
    case dumpTree(name: String)
    case dumpState(name: String)

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
}

public enum StateExpectation: Sendable {
    case equals(YAMLValue)
    case matches(String)
    case anyOf([YAMLValue])
}

public enum ScrollDirection: String, Sendable {
    case up, down, left, right
}

/// Restricted action vocabulary for `expect_change`. We deliberately do not
/// allow arbitrary nested steps — composition lives in `wait_for` chained with
/// regular steps. expect_change is the atomic do-then-observe shortcut.
public enum ExpectChangeAction: Sendable {
    case click(TargetRef)
    case doubleClick(TargetRef)
    case rightClick(TargetRef)
    case key(String)
    case type(String)
}

public enum TargetRef: Sendable {
    case id(String)
    case roleLabel(role: String, label: String)
    case label(String)
    case labelMatches(String)
    case treePath(String)
    case point(x: Double, y: Double)
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
    case countOf(TargetRef, equals: Int)
    case visible(TargetRef)
    case enabled(TargetRef)
    case focused(TargetRef)
    case state(viewmodel: String, path: String, expect: StateExpectation)
    case allOf([Predicate])
    case anyOf([Predicate])
    case not(Predicate)
    /// Window-existence shortcut: wait_for: { role: Window, title_matches: "..." }
    case window(title: String?, titleMatches: String?)
}

/// Simple time budget used by `wait_for` and per-spec `timeout` frontmatter.
public struct Duration: Sendable, Equatable {
    public var seconds: Double
    public init(seconds: Double) { self.seconds = seconds }

    public static let defaultWaitFor = Duration(seconds: 5)
    public static let defaultSpec = Duration(seconds: 60)
}
