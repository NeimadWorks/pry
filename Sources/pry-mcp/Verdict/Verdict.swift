import Foundation

public struct Verdict: Sendable {
    public enum Status: String, Sendable {
        case passed
        case failed
        case errored
        case timedOut = "timed_out"
    }

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

public struct StepResult: Sendable {
    public enum Outcome: String, Sendable {
        case passed
        case failed
        case errored
        case skipped
    }
    public var index: Int
    public var line: Int?
    public var source: String     // human-readable step description
    public var outcome: Outcome
    public var duration: TimeInterval
    public var message: String?
}

public struct FailureContext: Sendable {
    public var stepIndex: Int
    public var stepSource: String
    public var expected: String
    public var observed: String
    public var suggestion: String?
    public var axTreeSnippet: String?
    public var registeredState: String?
    public var relevantLogs: String?
    public var attachments: [String] // relative paths
}
