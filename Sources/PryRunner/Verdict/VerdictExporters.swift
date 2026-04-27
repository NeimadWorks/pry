import Foundation

/// Aggregate report formats for `run-suite`. The default is the per-spec
/// Markdown verdict; these exporters produce CI-friendly outputs across an
/// entire suite.
public enum VerdictExporters {

    /// JUnit XML — most CI systems consume this natively.
    public static func junit(_ verdicts: [Verdict]) -> String {
        let total = verdicts.count
        let failed = verdicts.filter { $0.status == .failed }.count
        let errored = verdicts.filter { $0.status == .errored || $0.status == .timedOut }.count
        let totalTime = verdicts.reduce(0.0) { $0 + $1.duration }

        var out = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        out += "<testsuite name=\"pry\" tests=\"\(total)\" failures=\"\(failed)\" errors=\"\(errored)\" time=\"\(String(format: "%.3f", totalTime))\">\n"
        for v in verdicts {
            let cls = v.app
            let name = v.specID
            let time = String(format: "%.3f", v.duration)
            switch v.status {
            case .passed:
                out += "  <testcase classname=\"\(escape(cls))\" name=\"\(escape(name))\" time=\"\(time)\"/>\n"
            case .failed:
                out += "  <testcase classname=\"\(escape(cls))\" name=\"\(escape(name))\" time=\"\(time)\">\n"
                if let f = v.failure {
                    out += "    <failure message=\"\(escape(f.observed))\">"
                    out += escape("Expected: \(f.expected)\nObserved: \(f.observed)")
                    out += "</failure>\n"
                } else {
                    out += "    <failure message=\"failed\"/>\n"
                }
                out += "  </testcase>\n"
            case .errored, .timedOut:
                out += "  <testcase classname=\"\(escape(cls))\" name=\"\(escape(name))\" time=\"\(time)\">\n"
                out += "    <error message=\"\(escape(v.errorKind ?? "errored"))\">"
                out += escape(v.errorMessage ?? "")
                out += "</error>\n"
                out += "  </testcase>\n"
            }
        }
        out += "</testsuite>\n"
        return out
    }

    /// TAP — Test Anything Protocol. Lightweight, scrollable, well supported.
    public static func tap(_ verdicts: [Verdict]) -> String {
        var out = "TAP version 13\n1..\(verdicts.count)\n"
        for (i, v) in verdicts.enumerated() {
            switch v.status {
            case .passed: out += "ok \(i + 1) - \(v.specID)\n"
            case .failed:
                out += "not ok \(i + 1) - \(v.specID)\n"
                if let f = v.failure {
                    out += "  ---\n  message: \"\(f.observed.replacingOccurrences(of: "\"", with: "\\\""))\"\n  ...\n"
                }
            case .errored, .timedOut:
                out += "not ok \(i + 1) - \(v.specID) # \(v.errorKind ?? "errored")\n"
            }
        }
        return out
    }

    /// Aggregate Markdown — one file summarizing the whole suite.
    public static func markdownSummary(_ verdicts: [Verdict]) -> String {
        let total = verdicts.count
        let passed = verdicts.filter { $0.status == .passed }.count
        let failed = verdicts.filter { $0.status == .failed }.count
        let errored = verdicts.filter { $0.status == .errored || $0.status == .timedOut }.count
        let dur = verdicts.reduce(0.0) { $0 + $1.duration }

        var out = "# Pry suite verdict\n\n"
        out += "**\(passed)/\(total) passed** "
        if failed > 0 { out += "· **\(failed) failed** " }
        if errored > 0 { out += "· **\(errored) errored**" }
        out += " · \(String(format: "%.1fs", dur)) total\n\n"
        out += "| Status | Spec | App | Duration |\n"
        out += "|---|---|---|---|\n"
        for v in verdicts {
            let icon: String
            switch v.status {
            case .passed: icon = "✅"
            case .failed: icon = "❌"
            case .errored: icon = "⚠️"
            case .timedOut: icon = "⏱"
            }
            out += "| \(icon) | `\(v.specID)` | `\(v.app)` | \(String(format: "%.1fs", v.duration)) |\n"
        }
        return out
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
         .replacingOccurrences(of: "<", with: "&lt;")
         .replacingOccurrences(of: ">", with: "&gt;")
         .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
