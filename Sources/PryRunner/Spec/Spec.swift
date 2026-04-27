import Foundation

/// A parsed Pry test spec.
public struct Spec: Sendable {
    public var id: String
    public var app: String          // bundle identifier
    public var description: String?
    public var tags: [String]
    public var timeout: Duration
    public var executablePath: String?  // non-standard, lets fixtures like DemoApp work
    public var sourcePath: String?
    public var steps: [Step]

    /// Raw source text for error reporting.
    public var sourceText: String

    public init(id: String, app: String, description: String?, tags: [String],
                timeout: Duration, executablePath: String?, sourcePath: String?,
                steps: [Step], sourceText: String) {
        self.id = id; self.app = app; self.description = description
        self.tags = tags; self.timeout = timeout
        self.executablePath = executablePath
        self.sourcePath = sourcePath
        self.steps = steps
        self.sourceText = sourceText
    }
}
