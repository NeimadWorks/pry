import Foundation

/// A parsed Pry test spec.
public struct Spec: Sendable {
    public var id: String
    public var app: String                    // bundle identifier
    public var description: String?
    public var tags: [String]
    public var timeout: Duration
    public var executablePath: String?
    public var sourcePath: String?

    // Wave 1 / 2
    public var animationsEnabled: Bool        // frontmatter: animations: off|on
    public var variables: [String: YAMLValue] // frontmatter `vars:` block
    public var setupSteps: [Step]
    public var teardownSteps: [Step]
    public var handlers: [SpecHandler]
    public var flows: [String: SpecFlow]

    // Wave 4 — fixtures & verdict richness
    public var withFS: FilesystemFixture?
    public var withDefaults: [String: YAMLValue]
    public var screenshotsPolicy: ScreenshotsPolicy

    // v0.2 verdict-richness knobs
    public var slowWarnMs: Int?            // step duration warning threshold
    public var stateDeltaPolicy: StateDeltaPolicy
    public var axTreeDiffPolicy: AxTreeDiffPolicy
    public var screenshotsEmbed: Bool      // base64-embed PNGs into verdict.md

    public var steps: [Step]

    /// Raw source text for error reporting.
    public var sourceText: String

    public init(id: String, app: String, description: String?, tags: [String],
                timeout: Duration, executablePath: String?, sourcePath: String?,
                animationsEnabled: Bool = true,
                variables: [String: YAMLValue] = [:],
                setupSteps: [Step] = [],
                teardownSteps: [Step] = [],
                handlers: [SpecHandler] = [],
                flows: [String: SpecFlow] = [:],
                withFS: FilesystemFixture? = nil,
                withDefaults: [String: YAMLValue] = [:],
                screenshotsPolicy: ScreenshotsPolicy = .onFailure,
                slowWarnMs: Int? = nil,
                stateDeltaPolicy: StateDeltaPolicy = .onFailure,
                axTreeDiffPolicy: AxTreeDiffPolicy = .onFailure,
                screenshotsEmbed: Bool = false,
                steps: [Step], sourceText: String) {
        self.id = id; self.app = app; self.description = description
        self.tags = tags; self.timeout = timeout
        self.executablePath = executablePath
        self.sourcePath = sourcePath
        self.animationsEnabled = animationsEnabled
        self.variables = variables
        self.setupSteps = setupSteps
        self.teardownSteps = teardownSteps
        self.handlers = handlers
        self.flows = flows
        self.withFS = withFS
        self.withDefaults = withDefaults
        self.screenshotsPolicy = screenshotsPolicy
        self.slowWarnMs = slowWarnMs
        self.stateDeltaPolicy = stateDeltaPolicy
        self.axTreeDiffPolicy = axTreeDiffPolicy
        self.screenshotsEmbed = screenshotsEmbed
        self.steps = steps
        self.sourceText = sourceText
    }
}

public enum StateDeltaPolicy: String, Sendable, Equatable {
    case off
    case onFailure = "on_failure"
    case everyStep = "every_step"
}

public enum AxTreeDiffPolicy: String, Sendable, Equatable {
    case off
    case onFailure = "on_failure"
}

public struct FilesystemFixture: Sendable {
    public var basePath: String              // e.g. "/tmp/pry-tests/${spec_id}"
    public var entries: [Entry]

    public enum Entry: Sendable {
        case file(path: String, content: String)
        case directory(path: String)
        case copy(path: String, source: String)
    }

    public init(basePath: String, entries: [Entry]) {
        self.basePath = basePath; self.entries = entries
    }
}

public enum ScreenshotsPolicy: String, Sendable {
    case never
    case onFailure = "on_failure"
    case everyStep = "every_step"
    case always
}

/// Async handler — runs in parallel to the main step list. Fires when its
/// trigger matches an incoming notification.
public struct SpecHandler: Sendable {
    public enum Trigger: Sendable {
        case sheetAppeared(titleMatches: String?)
        case stateChanged(viewmodel: String, path: String?)
        case windowAppeared(titleMatches: String?)
    }
    public enum Mode: String, Sendable { case once, always }

    public var name: String
    public var trigger: Trigger
    public var mode: Mode
    public var body: [Step]

    public init(name: String, trigger: Trigger, mode: Mode, body: [Step]) {
        self.name = name; self.trigger = trigger; self.mode = mode; self.body = body
    }
}

/// Reusable named sequence callable via `call: { name, args }`.
public struct SpecFlow: Sendable {
    public var name: String
    public var parameters: [String]
    public var body: [Step]

    public init(name: String, parameters: [String], body: [Step]) {
        self.name = name; self.parameters = parameters; self.body = body
    }
}
