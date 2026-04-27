import Foundation

/// Renders a `Verdict` into the canonical Markdown format defined in
/// `docs/design/verdict-format.md`. Frontmatter is stable YAML that consumers
/// (including Claude Code) can grep first.
public enum VerdictReporter {
    public static let pryVersion = "0.2.0"

    public static func render(_ v: Verdict, embedScreenshots: Bool = false) -> String {
        var out = ""
        out += renderFrontmatter(v)
        out += "\n"
        out += "# Verdict — \(v.specID)\n\n"

        switch v.status {
        case .passed:
            out += "**Status: PASSED** (\(v.stepsPassed)/\(v.stepsTotal) steps, \(format(v.duration)))\n\n"
            out += renderStepList(v.stepResults, successMode: true)
        case .failed:
            if let f = v.failure {
                out += "**Status: FAILED at step \(f.stepIndex)**\n\n"
                out += renderFailureSection(f, embedScreenshots: embedScreenshots)
                out += "\n## Preceding steps\n\n"
                out += renderStepList(v.stepResults, successMode: false)
            } else {
                out += "**Status: FAILED**\n\n"
                out += renderStepList(v.stepResults, successMode: false)
            }
        case .errored:
            out += "**Status: ERRORED**\n\n"
            out += "**Error kind:** `\(v.errorKind ?? "unknown")`\n\n"
            if let m = v.errorMessage { out += "**Message:** \(m)\n\n" }
            out += renderStepList(v.stepResults, successMode: false)
        case .timedOut:
            out += "**Status: TIMED OUT** (after \(format(v.duration)))\n\n"
            out += renderStepList(v.stepResults, successMode: false)
        }
        return out
    }

    // MARK: - Frontmatter

    private static func renderFrontmatter(_ v: Verdict) -> String {
        let iso = ISO8601DateFormatter()
        var lines: [String] = ["---"]
        if let p = v.specPath { lines.append("spec: \(p)") }
        lines.append("id: \(v.specID)")
        lines.append("app: \(v.app)")
        lines.append("status: \(v.status.rawValue)")
        lines.append(String(format: "duration: %.1fs", v.duration))
        lines.append("steps_total: \(v.stepsTotal)")
        lines.append("steps_passed: \(v.stepsPassed)")
        if let failed = v.failedAtStep {
            lines.append("failed_at_step: \(failed)")
        } else {
            lines.append("failed_at_step: null")
        }
        lines.append("pry_version: \(pryVersion)")
        lines.append("pry_spec_version: 1")
        lines.append("started_at: \(iso.string(from: v.startedAt))")
        lines.append("finished_at: \(iso.string(from: v.finishedAt))")
        if let kind = v.errorKind {
            lines.append("error_kind: \(kind)")
        }
        lines.append("---")
        return lines.joined(separator: "\n") + "\n"
    }

    // MARK: - Failure section

    private static func renderFailureSection(_ f: FailureContext, embedScreenshots: Bool = false) -> String {
        var out = ""
        out += "## Step \(f.stepIndex) — `\(f.stepSource)`\n\n"
        out += "**Expected:** \(f.expected)\n"
        out += "**Observed:** \(f.observed)\n\n"
        if let s = f.suggestion {
            out += "**Suggestion:** \(s)\n\n"
        }
        if let snippet = f.axTreeSnippet {
            out += "### AX tree context at failure\n\n```yaml\n\(snippet)\n```\n\n"
        }
        if let diff = f.axTreeDiff {
            out += "### AX tree diff (launch → failure)\n\n```diff\n\(diff)\n```\n\n"
        }
        if let state = f.registeredState {
            out += "### Registered state at failure\n\n```yaml\n\(state)\n```\n\n"
        }
        if let timeline = f.stateDeltaTimeline {
            out += "### State delta timeline\n\n\(timeline)\n\n"
        }
        if let logs = f.relevantLogs {
            out += "### Relevant logs\n\n```\n\(logs)\n```\n\n"
        }
        if !f.attachments.isEmpty {
            out += "### Attachments\n\n"
            for a in f.attachments {
                out += "- `\(a)`\n"
                if embedScreenshots, a.hasSuffix(".png"),
                   let data = try? Data(contentsOf: URL(fileURLWithPath: a)) {
                    let b64 = data.base64EncodedString()
                    out += "  ![](data:image/png;base64,\(b64))\n"
                }
            }
            out += "\n"
        }
        return out
    }

    // MARK: - Step list

    private static func renderStepList(_ results: [StepResult], successMode: Bool) -> String {
        guard !results.isEmpty else { return "" }
        var out = successMode ? "" : ""
        for r in results {
            let icon: String
            switch r.outcome {
            case .passed: icon = "✅"
            case .failed: icon = "❌"
            case .errored: icon = "⚠️"
            case .skipped: icon = "⏭"
            }
            var line = "- \(icon) Step \(r.index) — `\(r.source)` (\(format(r.duration)))"
            if let m = r.message, !m.isEmpty { line += " — \(m)" }
            out += line + "\n"
        }
        return out
    }

    // MARK: -

    private static func format(_ d: TimeInterval) -> String {
        if d < 1 { return String(format: "%.0fms", d * 1000) }
        return String(format: "%.1fs", d)
    }
}
