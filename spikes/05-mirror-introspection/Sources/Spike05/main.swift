import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Spike 5 — Mirror + PryInspectable under Swift 6 strict concurrency
//
// Binary question:
//   Does the PryInspectable pattern correctly expose @Published values from
//   a @MainActor ObservableObject via prySnapshot()? Any Sendable gotchas?
//
// Method:
//   1. Compile-time check already covered by DemoApp building under strict concurrency
//      with @MainActor protocol + [String: any Sendable] return type. Building
//      DemoApp without warnings is half of the PASS condition.
//   2. Runtime check: launch DemoApp, click the "new_doc_button" to trigger
//      vm.createDocument(), read the state_snapshot JSON line from the marker
//      file, verify it contains the expected keys with expected updated values.
//   3. Also verify pry_registered marker fires at app startup (confirms the
//      registry's generic constraint and the weak-reference closure compile
//      and execute).
//
// PASS if all expected keys are present with expected values after the click,
// AND pry_registered was observed at startup.

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: spike05 <absolute-path-to-DemoApp-binary>\n", stderr)
    exit(2)
}

let resolvedBinary = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard FileManager.default.isExecutableFile(atPath: resolvedBinary.path) else {
    fputs("[spike05] not an executable at: \(resolvedBinary.path)\n", stderr)
    exit(2)
}

let markerFile = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("pry-spike05-\(UUID().uuidString).marker")

func log(_ s: String) { FileHandle.standardError.write(Data("[spike05] \(s)\n".utf8)) }

if !AXIsProcessTrusted() {
    log("FAIL — not trusted for Accessibility.")
    exit(1)
}

// Launch DemoApp
let process = Process()
process.executableURL = resolvedBinary
process.environment = ProcessInfo.processInfo.environment.merging([
    "PRY_MARKER_FILE": markerFile.path
]) { _, new in new }
process.standardOutput = Pipe()
process.standardError = Pipe()

do { try process.run() } catch {
    log("FAIL — launch error: \(error)"); exit(1)
}
defer { if process.isRunning { process.terminate() } }

let pid = process.processIdentifier
log("launched DemoApp pid=\(pid)")
log("marker: \(markerFile.path)")

// MARK: - AX helpers (just enough to click the button)

func axValue<T>(_ element: AXUIElement, _ attr: String, as: T.Type) -> T? {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, attr as CFString, &value)
    guard err == .success, let value else { return nil }
    return value as? T
}

func axChildren(_ element: AXUIElement) -> [AXUIElement] {
    var value: CFTypeRef?
    let err = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value)
    guard err == .success, let arr = value as? [AXUIElement] else { return [] }
    return arr
}

func axIdentifier(_ element: AXUIElement) -> String? {
    axValue(element, "AXIdentifier", as: String.self)
}

func axFrame(_ element: AXUIElement) -> CGRect? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
    let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
    guard posErr == .success, sizeErr == .success else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let posValue { AXValueGetValue(posValue as! AXValue, .cgPoint, &origin) }
    if let sizeValue { AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) }
    return CGRect(origin: origin, size: size)
}

func findElement(root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(root) { return root }
    for child in axChildren(root) {
        if let hit = findElement(root: child, matching: predicate) { return hit }
    }
    return nil
}

func postClick(at point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cgSessionEventTap)
    usleep(30_000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)?.post(tap: .cgSessionEventTap)
}

func markerContents() -> String {
    (try? String(contentsOf: markerFile, encoding: .utf8)) ?? ""
}

func waitForLine(containing needle: String, timeout: TimeInterval) -> String? {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        for line in markerContents().split(separator: "\n") where line.contains(needle) {
            return String(line)
        }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return nil
}

// Wait for pry_registered — this proves the registry generic + weak-ref closure ran.
guard let registeredLine = waitForLine(containing: "pry_registered", timeout: 5) else {
    log("FAIL — pry_registered marker never appeared. Registry did not fire.")
    exit(1)
}
log("observed: \(registeredLine)")

// Click new_doc_button
let app = AXUIElementCreateApplication(pid)
var button: AXUIElement?
let deadline = Date().addingTimeInterval(5)
while Date() < deadline {
    button = findElement(root: app) { axIdentifier($0) == "new_doc_button" }
    if button != nil { break }
    Thread.sleep(forTimeInterval: 0.1)
}
guard let button, let frame = axFrame(button) else {
    log("FAIL — could not resolve new_doc_button")
    exit(1)
}
postClick(at: CGPoint(x: frame.midX, y: frame.midY))
log("clicked new_doc_button")

// Wait for state_snapshot line
guard let snapshotLine = waitForLine(containing: "state_snapshot", timeout: 3) else {
    log("FAIL — no state_snapshot in marker file within 3s")
    exit(1)
}
log("observed: \(snapshotLine)")

// Parse JSON tail
// Format: "<ts> state_snapshot {json}"
guard let braceRange = snapshotLine.range(of: "{") else {
    log("FAIL — snapshot line has no JSON payload")
    exit(1)
}
let jsonStr = String(snapshotLine[braceRange.lowerBound...])
guard let jsonData = jsonStr.data(using: .utf8),
      let parsed = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
    log("FAIL — could not parse snapshot JSON: \(jsonStr)")
    exit(1)
}
log("parsed snapshot: \(parsed)")

// Validate shape
let viewmodel = parsed["viewmodel"] as? String
let keys = parsed["keys"] as? [String: Any]

var problems: [String] = []
if viewmodel != "DocumentListVM" {
    problems.append("viewmodel expected 'DocumentListVM', got '\(viewmodel ?? "nil")'")
}
guard let keys else {
    problems.append("keys field missing or wrong type")
    log("FAIL — \(problems.joined(separator: "; "))")
    exit(1)
}

let expectedInts: [String: Int] = [
    "documents.count": 1,
    "clickCount": 1,
    "zoneTapCount": 0,
]
for (k, expected) in expectedInts {
    guard let got = keys[k] as? Int else {
        problems.append("\(k) missing or not Int")
        continue
    }
    if got != expected {
        problems.append("\(k) expected \(expected), got \(got)")
    }
}

if let verbose = keys["verbose"] as? Bool {
    if verbose != false {
        problems.append("verbose expected false, got \(verbose)")
    }
} else {
    problems.append("verbose missing or not Bool")
}

if let draft = keys["draftName"] as? String {
    if draft != "" {
        problems.append("draftName expected '', got '\(draft)'")
    }
} else {
    problems.append("draftName missing or not String")
}

if problems.isEmpty {
    log("PASS — PryInspectable + PryRegistry delivered the expected snapshot after a MainActor state mutation; no Sendable gotchas observed (compilation clean, runtime values match).")
    exit(0)
} else {
    for p in problems { log("  problem: \(p)") }
    log("FAIL — snapshot did not match expectations")
    exit(1)
}
