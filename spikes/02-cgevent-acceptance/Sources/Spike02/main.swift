import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Spike 2 — Synthetic CGEvent acceptance
//
// Binary question:
//   Does CGEventPost(.cgSessionEventTap, ...) at AX-resolved coordinates
//   reliably trigger a SwiftUI Button action on macOS 14+?
//
// Method:
//   1. Launch DemoApp as a subprocess with PRY_MARKER_FILE set.
//   2. Wait for its window to appear (AX poll).
//   3. Resolve the "new_doc_button" AXUIElement and read its frame.
//   4. Inject mouseDown+mouseUp at the frame's center via CGEventPost.
//   5. Wait briefly, read the marker file.
//   6. If marker contains "button_clicked" → PASS.
//
// Preconditions:
//   - The process running this spike must have Accessibility permission
//     (System Settings → Privacy & Security → Accessibility).
//     Granting Terminal (or the IDE running swift run) is sufficient.

// MARK: - Config

struct Config {
    let demoAppBinary: URL
    let markerFile: URL
    let buttonID: String = "new_doc_button"
    let launchTimeout: TimeInterval = 5
    let clickTimeout: TimeInterval = 2
}

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: spike02 <path-to-DemoApp-binary>\n", stderr)
    fputs("  typically: Fixtures/DemoApp/.build/debug/DemoApp\n", stderr)
    exit(2)
}

let rawBinaryArg = CommandLine.arguments[1]
let resolvedBinary = URL(fileURLWithPath: rawBinaryArg).standardizedFileURL
guard FileManager.default.isExecutableFile(atPath: resolvedBinary.path) else {
    fputs("[spike02] FAIL — not an executable file at: \(resolvedBinary.path)\n", stderr)
    fputs("[spike02] pass an absolute path, or a path relative to the current working directory.\n", stderr)
    exit(1)
}

let config = Config(
    demoAppBinary: resolvedBinary,
    markerFile: URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("pry-spike02-\(UUID().uuidString).marker")
)

// MARK: - AX helpers

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

func findElement(root: AXUIElement, matching predicate: (AXUIElement) -> Bool) -> AXUIElement? {
    if predicate(root) { return root }
    for child in axChildren(root) {
        if let hit = findElement(root: child, matching: predicate) { return hit }
    }
    return nil
}

func elementIdentifier(_ element: AXUIElement) -> String? {
    axValue(element, "AXIdentifier", as: String.self)
}

func elementFrame(_ element: AXUIElement) -> CGRect? {
    var posValue: CFTypeRef?
    var sizeValue: CFTypeRef?
    let posErr = AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &posValue)
    let sizeErr = AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue)
    guard posErr == .success, sizeErr == .success else { return nil }
    var origin = CGPoint.zero
    var size = CGSize.zero
    if let posValue {
        AXValueGetValue(posValue as! AXValue, .cgPoint, &origin)
    }
    if let sizeValue {
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
    }
    return CGRect(origin: origin, size: size)
}

// MARK: - Event injection

func postClick(at point: CGPoint) {
    let source = CGEventSource(stateID: .hidSystemState)

    let down = CGEvent(mouseEventSource: source,
                       mouseType: .leftMouseDown,
                       mouseCursorPosition: point,
                       mouseButton: .left)
    let up = CGEvent(mouseEventSource: source,
                     mouseType: .leftMouseUp,
                     mouseCursorPosition: point,
                     mouseButton: .left)

    down?.post(tap: .cgSessionEventTap)
    usleep(30_000) // 30ms — Spike 2 pins this value if needed
    up?.post(tap: .cgSessionEventTap)
}

// MARK: - Runner

func log(_ message: String) {
    FileHandle.standardError.write(Data("[spike02] \(message)\n".utf8))
}

func fail(_ reason: String) -> Never {
    log("FAIL — \(reason)")
    exit(1)
}

func pass(_ note: String) -> Never {
    log("PASS — \(note)")
    exit(0)
}

// Pre-flight: AX trust.
if !AXIsProcessTrusted() {
    fail("this process is not trusted for Accessibility. Grant in System Settings → Privacy & Security → Accessibility, then re-run.")
}

// Launch DemoApp
let process = Process()
process.executableURL = config.demoAppBinary
process.environment = ProcessInfo.processInfo.environment.merging([
    "PRY_MARKER_FILE": config.markerFile.path
]) { _, new in new }

let stdoutPipe = Pipe()
let stderrPipe = Pipe()
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

do {
    try process.run()
} catch {
    fail("could not launch DemoApp at \(config.demoAppBinary.path): \(error)")
}

let demoPid = process.processIdentifier
log("launched DemoApp pid=\(demoPid)")
log("marker file: \(config.markerFile.path)")

defer {
    if process.isRunning { process.terminate() }
}

// Poll until window + target button are visible
let appElement = AXUIElementCreateApplication(demoPid)
var foundButton: AXUIElement?
let deadline = Date().addingTimeInterval(config.launchTimeout)

while Date() < deadline {
    foundButton = findElement(root: appElement) { el in
        elementIdentifier(el) == config.buttonID
    }
    if foundButton != nil { break }
    Thread.sleep(forTimeInterval: 0.1)
}

guard let button = foundButton else {
    fail("did not find AX element with AXIdentifier=\(config.buttonID) within \(Int(config.launchTimeout))s")
}

guard let frame = elementFrame(button) else {
    fail("found button but could not read its frame")
}

log("resolved button frame: \(frame)")

// AX frame origin is in screen coords (top-left on macOS is (0,0) for AX;
// CGEventPost uses the same flipped coord system). Center of frame:
let clickPoint = CGPoint(x: frame.midX, y: frame.midY)
log("clicking at \(clickPoint)")

postClick(at: clickPoint)

// Wait for marker file to appear/update
let watchDeadline = Date().addingTimeInterval(config.clickTimeout)
var markerContent = ""
while Date() < watchDeadline {
    if let data = try? Data(contentsOf: config.markerFile),
       let text = String(data: data, encoding: .utf8),
       text.contains("button_clicked") {
        markerContent = text
        break
    }
    Thread.sleep(forTimeInterval: 0.05)
}

if markerContent.isEmpty {
    log("marker file contents: <empty>")
    fail("no button_clicked marker observed within \(config.clickTimeout)s — click did not reach the Button action")
}

log("marker observed: \(markerContent.trimmingCharacters(in: .whitespacesAndNewlines))")
pass("CGEventPost(.cgSessionEventTap) at AX-resolved coords triggered the SwiftUI Button action")
