import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

// MARK: - Combined spike — answers both
//
// Spike 1: Do AX frames match hit-test regions for multiple SwiftUI view types?
// Spike 3: Does .accessibilityIdentifier propagate as AXIdentifier across view types?
//
// Method:
//   1. Launch DemoApp with PRY_MARKER_FILE set.
//   2. Enumerate the AX tree once; record every element carrying AXIdentifier.
//   3. For each expected identifier: present? role? frame within window bounds?
//   4. For clickable targets (Button, Toggle, custom tap zone): inject click at
//      frame center, check that the expected marker event appears.
//   5. Emit a PASS/FAIL table and a pair of verdicts.

// MARK: - Expectations

struct Target {
    let id: String
    let clickable: Bool
    let markerEvent: String?       // expected event in marker file after click
    let note: String
}

let targets: [Target] = [
    .init(id: "new_doc_button", clickable: true,  markerEvent: "button_clicked", note: "SwiftUI Button"),
    .init(id: "verbose_toggle", clickable: true,  markerEvent: "toggle_changed", note: "SwiftUI Toggle"),
    .init(id: "tap_zone",       clickable: true,  markerEvent: "zone_tapped",    note: "custom .onTapGesture on Rectangle"),
    .init(id: "doc_name_field", clickable: false, markerEvent: nil,              note: "SwiftUI TextField"),
    .init(id: "click_counter",  clickable: false, markerEvent: nil,              note: "SwiftUI Text (static)"),
    .init(id: "doc_list",       clickable: false, markerEvent: nil,              note: "SwiftUI List"),
]

// MARK: - Args

guard CommandLine.arguments.count >= 2 else {
    fputs("usage: spike01 <absolute-path-to-DemoApp-binary>\n", stderr)
    exit(2)
}

let resolvedBinary = URL(fileURLWithPath: CommandLine.arguments[1]).standardizedFileURL
guard FileManager.default.isExecutableFile(atPath: resolvedBinary.path) else {
    fputs("[spike01] not an executable at: \(resolvedBinary.path)\n", stderr)
    exit(2)
}

let markerFile = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("pry-spike01-\(UUID().uuidString).marker")

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

func axRole(_ element: AXUIElement) -> String {
    axValue(element, kAXRoleAttribute, as: String.self) ?? "?"
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

func walk(_ element: AXUIElement, visit: (AXUIElement) -> Void) {
    visit(element)
    for child in axChildren(element) {
        walk(child, visit: visit)
    }
}

func findWindow(_ appElement: AXUIElement) -> (AXUIElement, CGRect)? {
    guard let windows: [AXUIElement] = axValue(appElement, kAXWindowsAttribute, as: [AXUIElement].self),
          let first = windows.first else { return nil }
    return (first, axFrame(first) ?? .zero)
}

// MARK: - Event injection (reuse Spike 2 pattern)

func postClick(at point: CGPoint) {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
    let up   = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp,   mouseCursorPosition: point, mouseButton: .left)
    down?.post(tap: .cgSessionEventTap)
    usleep(30_000)
    up?.post(tap: .cgSessionEventTap)
}

// MARK: - Marker file helpers

func markerContents() -> String {
    (try? String(contentsOf: markerFile, encoding: .utf8)) ?? ""
}

func waitForMarker(containing needle: String, since cursor: Int, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        let all = markerContents()
        if all.count > cursor,
           String(all.dropFirst(cursor)).contains(needle) { return true }
        Thread.sleep(forTimeInterval: 0.05)
    }
    return false
}

// MARK: - Runner

func log(_ s: String) { FileHandle.standardError.write(Data("[spike01] \(s)\n".utf8)) }

if !AXIsProcessTrusted() {
    log("FAIL — not trusted for Accessibility. Grant in System Settings → Privacy & Security → Accessibility.")
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

// Wait for window
let app = AXUIElementCreateApplication(pid)
var windowInfo: (AXUIElement, CGRect)?
let launchDeadline = Date().addingTimeInterval(5)
while Date() < launchDeadline {
    if let w = findWindow(app) { windowInfo = w; break }
    Thread.sleep(forTimeInterval: 0.1)
}
guard let (window, windowFrame) = windowInfo else {
    log("FAIL — app window not detected within 5s")
    exit(1)
}
log("window frame: \(windowFrame)")

// Give SwiftUI a beat to finish first layout.
Thread.sleep(forTimeInterval: 0.4)

// Collect every element carrying AXIdentifier
var byId: [String: AXUIElement] = [:]
walk(window) { el in
    if let id = axIdentifier(el) { byId[id] = el }
}

// Emit table
struct Row {
    let id: String
    let present: Bool
    let role: String
    let frame: CGRect?
    let frameSane: Bool
    let clickable: Bool
    let clickFired: Bool?   // nil = n/a
}

var rows: [Row] = []

for t in targets {
    let el = byId[t.id]
    if let el {
        let role = axRole(el)
        let frame = axFrame(el)
        let sane: Bool = {
            guard let f = frame else { return false }
            guard f.width > 0, f.height > 0 else { return false }
            // frame must intersect window
            return f.intersects(windowFrame)
        }()

        var fired: Bool? = nil
        if t.clickable, let f = frame, let ev = t.markerEvent {
            let before = markerContents().count
            let p = CGPoint(x: f.midX, y: f.midY)
            postClick(at: p)
            fired = waitForMarker(containing: ev, since: before, timeout: 1.5)
        }

        rows.append(Row(id: t.id, present: true, role: role, frame: frame, frameSane: sane,
                        clickable: t.clickable, clickFired: fired))
    } else {
        rows.append(Row(id: t.id, present: false, role: "-", frame: nil, frameSane: false,
                        clickable: t.clickable, clickFired: nil))
    }
}

// Report
log("")
log(String(format: "%-20s %-8s %-18s %-28s %-6s %-6s", "identifier", "present", "role", "frame", "sane", "click"))
log(String(repeating: "-", count: 90))
for r in rows {
    let frameStr: String
    if let f = r.frame {
        frameStr = String(format: "(%.0f,%.0f,%.0f,%.0f)", f.origin.x, f.origin.y, f.size.width, f.size.height)
    } else { frameStr = "-" }
    let click: String
    if r.clickable {
        click = r.clickFired == true ? "✓" : "✗"
    } else { click = "n/a" }
    log(String(format: "%-20s %-8s %-18s %-28s %-6s %-6s",
               r.id, r.present ? "✓" : "✗", r.role, frameStr, r.frameSane ? "✓" : "✗", click))
}
log("")

// Verdicts
let spike3Pass = rows.allSatisfy { $0.present }
let spike1Pass = rows.allSatisfy { r in
    guard r.present, r.frameSane else { return false }
    if r.clickable { return r.clickFired == true }
    return true
}

log("Spike 3 (AXIdentifier propagation): \(spike3Pass ? "PASS" : "FAIL")")
log("Spike 1 (AX frames reliability):    \(spike1Pass ? "PASS" : "FAIL")")

if !spike3Pass {
    let missing = rows.filter { !$0.present }.map { $0.id }
    log("  missing identifiers: \(missing.joined(separator: ", "))")
}
if !spike1Pass {
    let badFrame = rows.filter { $0.present && !$0.frameSane }.map { $0.id }
    let badClick = rows.filter { $0.clickable && $0.clickFired != true }.map { $0.id }
    if !badFrame.isEmpty { log("  unsane frames: \(badFrame.joined(separator: ", "))") }
    if !badClick.isEmpty { log("  click did not fire marker: \(badClick.joined(separator: ", "))") }
}

exit((spike1Pass && spike3Pass) ? 0 : 1)
