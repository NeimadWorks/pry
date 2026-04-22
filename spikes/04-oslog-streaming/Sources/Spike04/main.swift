import Foundation

// MARK: - Spike 4 — OSLogStore streaming latency
//
// Binary question:
//   Can an in-process OSLogStore tail pick up a freshly emitted log entry
//   in < 200 ms? Is subsystem filtering stable?
//
// Method:
//   DemoApp runs its own measurement loop when launched with
//   PRY_SPIKE_LOG_LATENCY=1. For N iterations it emits a tagged log line,
//   polls `OSLogStore(scope: .currentProcessIdentifier)` with a
//   subsystem+category predicate, and records how long until the tag is
//   visible. After the loop it writes `log_latency_complete` to the marker
//   file with p50, p95, max, and the raw samples, then terminates.
//
//   This spike runner just:
//     - launches DemoApp with that env flag,
//     - waits for `log_latency_complete` in the marker file,
//     - parses the JSON stats,
//     - verdicts PASS if p95 < 200 ms AND timeouts == 0.
//
// Rationale for in-process measurement:
//   OSLogStore(.system) requires com.apple.developer.system-log, which we
//   don't want for Pry. PryHarness will always tail its own process's logs,
//   so this spike measures the thing that will actually happen.

let threshold = 200.0 // ms

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: spike04 <absolute-path-to-DemoApp-binary>\n", stderr)
    exit(2)
}

let resolvedBinary = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard FileManager.default.isExecutableFile(atPath: resolvedBinary.path) else {
    fputs("[spike04] not an executable at: \(resolvedBinary.path)\n", stderr)
    exit(2)
}

let markerFile = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("pry-spike04-\(UUID().uuidString).marker")

func log(_ s: String) { FileHandle.standardError.write(Data("[spike04] \(s)\n".utf8)) }

// No AX needed for this spike, but respect the pattern.
let process = Process()
process.executableURL = resolvedBinary
process.environment = ProcessInfo.processInfo.environment.merging([
    "PRY_MARKER_FILE": markerFile.path,
    "PRY_SPIKE_LOG_LATENCY": "1",
]) { _, new in new }
process.standardOutput = Pipe()
process.standardError = Pipe()

do { try process.run() } catch {
    log("FAIL — launch error: \(error)"); exit(1)
}
defer { if process.isRunning { process.terminate() } }

log("launched DemoApp pid=\(process.processIdentifier)")
log("marker: \(markerFile.path)")
log("measuring up to 60s for 10 iterations...")

// Wait for completion (generous: iterations × perIterationTimeout + margin).
let deadline = Date().addingTimeInterval(60)
var completeLine: String?
while Date() < deadline {
    let contents = (try? String(contentsOf: markerFile, encoding: .utf8)) ?? ""
    for line in contents.split(separator: "\n") where line.contains("log_latency_complete") {
        completeLine = String(line); break
    }
    if completeLine != nil { break }
    Thread.sleep(forTimeInterval: 0.1)
}

guard let completeLine else {
    log("FAIL — no log_latency_complete marker within 60s")
    exit(1)
}

log("observed: \(completeLine)")

// Parse JSON tail
guard let brace = completeLine.range(of: "{") else {
    log("FAIL — no JSON payload in line")
    exit(1)
}
let json = String(completeLine[brace.lowerBound...])
guard let data = json.data(using: .utf8),
      let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
    log("FAIL — could not parse JSON: \(json)")
    exit(1)
}

let p50 = dict["p50_ms"] as? Double ?? -1
let p95 = dict["p95_ms"] as? Double ?? -1
let maxV = dict["max_ms"] as? Double ?? -1
let timeouts = dict["timeouts"] as? Int ?? -1
let iterations = dict["iterations"] as? Int ?? -1
let samples = dict["samples_ms"] as? [Double] ?? []

log("")
log("iterations: \(iterations)")
log("timeouts:   \(timeouts)")
log(String(format: "p50:        %.1f ms", p50))
log(String(format: "p95:        %.1f ms", p95))
log(String(format: "max:        %.1f ms", maxV))
log("samples_ms: \(samples.map { String(format: "%.0f", $0) }.joined(separator: " "))")
log("")

let pass = timeouts == 0 && p95 >= 0 && p95 < threshold
log("threshold:  p95 < \(Int(threshold)) ms, no timeouts")
log(pass ? "PASS" : "FAIL")
exit(pass ? 0 : 1)
