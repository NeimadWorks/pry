import Foundation
import OSLog

/// Best-effort OSLog reader for the current process.
///
/// Spike 4 (2026-04-22) measured ~1 s floor on `OSLogStore.getEntries()` for
/// same-process reads. This tap ships with that understanding: it feeds
/// `pry_logs` and the "Relevant logs" section of verdicts (post-hoc), not
/// real-time assertions. See [ADR-006].
public enum PryLogTap {

    public struct Line: Sendable {
        public let date: Date
        public let level: String
        public let subsystem: String?
        public let category: String?
        public let message: String
    }

    /// Read log entries since `since` (or the last few seconds if nil).
    public static func readLines(since: Date?, subsystem: String?) -> [Line] {
        guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else {
            return []
        }
        let anchor = since ?? Date().addingTimeInterval(-5)
        let position = store.position(date: anchor)
        var out: [Line] = []
        do {
            let entries = try store.getEntries(at: position)
            for entry in entries {
                guard let e = entry as? OSLogEntryLog else { continue }
                if let sub = subsystem, e.subsystem != sub { continue }
                out.append(Line(
                    date: e.date,
                    level: levelString(e.level),
                    subsystem: e.subsystem,
                    category: e.category,
                    message: e.composedMessage
                ))
            }
        } catch {
            return []
        }
        return out
    }

    private static func levelString(_ l: OSLogEntryLog.Level) -> String {
        switch l {
        case .undefined: return "undefined"
        case .debug: return "debug"
        case .info: return "info"
        case .notice: return "notice"
        case .error: return "error"
        case .fault: return "fault"
        @unknown default: return "unknown"
        }
    }
}
