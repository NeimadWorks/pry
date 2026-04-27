import Foundation
import AppKit
import CoreGraphics

/// CGEvent-based event injection. All events go through `cgSessionEventTap` so
/// they exercise the real OS → AppKit → SwiftUI path. Spike 2 (2026-04-22)
/// validated this approach.
public enum EventInjector {
    public enum InjectError: Error, CustomStringConvertible {
        case eventCreateFailed(String)
        case unknownKey(String)

        public var description: String {
            switch self {
            case .eventCreateFailed(let what): return "CGEvent creation failed for: \(what)"
            case .unknownKey(let k): return "unknown key name: \(k)"
            }
        }
    }

    // MARK: - Mouse

    public static func click(at point: CGPoint, modifiers: CGEventFlags = []) throws {
        try press(.leftMouseDown, .leftMouseUp, at: point, flags: modifiers)
    }

    public static func doubleClick(at point: CGPoint, modifiers: CGEventFlags = []) throws {
        try press(.leftMouseDown, .leftMouseUp, at: point, clickCount: 2, flags: modifiers)
    }

    public static func rightClick(at point: CGPoint, modifiers: CGEventFlags = []) throws {
        try press(.rightMouseDown, .rightMouseUp, at: point, button: .right, flags: modifiers)
    }

    /// Long press: mouseDown, hold for `dwellMs`, mouseUp.
    public static func longPress(at point: CGPoint, dwellMs: Int = 800) throws {
        let s = source
        guard let d = CGEvent(mouseEventSource: s, mouseType: .leftMouseDown,
                              mouseCursorPosition: point, mouseButton: .left),
              let u = CGEvent(mouseEventSource: s, mouseType: .leftMouseUp,
                              mouseCursorPosition: point, mouseButton: .left) else {
            throw InjectError.eventCreateFailed("longPress")
        }
        d.post(tap: .cgSessionEventTap)
        usleep(useconds_t(dwellMs * 1000))
        u.post(tap: .cgSessionEventTap)
    }

    /// Hover with a dwell — useful for waking tooltips & hover popovers.
    public static func hoverDwell(at point: CGPoint, dwellMs: Int = 800) throws {
        try move(to: point)
        usleep(useconds_t(dwellMs * 1000))
    }

    public static func move(to point: CGPoint) throws {
        guard let e = CGEvent(mouseEventSource: source, mouseType: .mouseMoved,
                              mouseCursorPosition: point, mouseButton: .left) else {
            throw InjectError.eventCreateFailed("mouseMoved")
        }
        e.post(tap: .cgSessionEventTap)
    }

    /// Drag from one point to another. Posts mouseDown at `from`, a sequence of
    /// interpolated mouseDragged events to look human-ish, then mouseUp at `to`.
    /// `steps` controls the number of intermediate moves (>= 1).
    public static func drag(from: CGPoint, to: CGPoint, steps: Int = 12, dwellMicros: useconds_t = 12_000) throws {
        guard let down = CGEvent(mouseEventSource: source, mouseType: .leftMouseDown,
                                 mouseCursorPosition: from, mouseButton: .left) else {
            throw InjectError.eventCreateFailed("leftMouseDown")
        }
        down.post(tap: .cgSessionEventTap)
        usleep(dwellMicros)

        let n = max(1, steps)
        for i in 1...n {
            let t = Double(i) / Double(n)
            let p = CGPoint(x: from.x + (to.x - from.x) * t,
                            y: from.y + (to.y - from.y) * t)
            guard let m = CGEvent(mouseEventSource: source, mouseType: .leftMouseDragged,
                                  mouseCursorPosition: p, mouseButton: .left) else {
                throw InjectError.eventCreateFailed("leftMouseDragged")
            }
            m.post(tap: .cgSessionEventTap)
            usleep(dwellMicros)
        }

        guard let up = CGEvent(mouseEventSource: source, mouseType: .leftMouseUp,
                               mouseCursorPosition: to, mouseButton: .left) else {
            throw InjectError.eventCreateFailed("leftMouseUp")
        }
        up.post(tap: .cgSessionEventTap)
    }

    /// Scroll wheel events at a given on-screen point. Direction is encoded as
    /// signed deltas in the scroll vector; `amount` is the number of "lines".
    /// On macOS the wheel coordinate space is flipped: positive Y scrolls up.
    public static func scroll(at point: CGPoint, dx: Int32, dy: Int32) throws {
        // Move cursor first so the target window receives the scroll.
        try move(to: point)
        usleep(5_000)
        guard let e = CGEvent(scrollWheelEvent2Source: source,
                              units: .line,
                              wheelCount: 2,
                              wheel1: dy,
                              wheel2: dx,
                              wheel3: 0) else {
            throw InjectError.eventCreateFailed("scrollWheelEvent")
        }
        e.post(tap: .cgSessionEventTap)
    }

    private static func press(_ down: CGEventType, _ up: CGEventType, at point: CGPoint,
                              button: CGMouseButton = .left, clickCount: Int = 1,
                              flags: CGEventFlags = []) throws {
        guard let d = CGEvent(mouseEventSource: source, mouseType: down,
                              mouseCursorPosition: point, mouseButton: button) else {
            throw InjectError.eventCreateFailed("\(down)")
        }
        guard let u = CGEvent(mouseEventSource: source, mouseType: up,
                              mouseCursorPosition: point, mouseButton: button) else {
            throw InjectError.eventCreateFailed("\(up)")
        }
        if clickCount > 1 {
            d.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
            u.setIntegerValueField(.mouseEventClickState, value: Int64(clickCount))
        }
        if !flags.isEmpty {
            d.flags = flags
            u.flags = flags
        }
        d.post(tap: .cgSessionEventTap)
        usleep(30_000)
        u.post(tap: .cgSessionEventTap)
    }

    // MARK: - Modifier helpers

    public static func parseModifiers(_ tokens: [String]) -> CGEventFlags {
        var f: CGEventFlags = []
        for t in tokens {
            switch t.lowercased() {
            case "cmd", "command", "⌘": f.insert(.maskCommand)
            case "shift", "⇧": f.insert(.maskShift)
            case "opt", "option", "alt", "⌥": f.insert(.maskAlternate)
            case "ctrl", "control", "⌃": f.insert(.maskControl)
            case "fn", "function": f.insert(.maskSecondaryFn)
            default: break
            }
        }
        return f
    }

    // MARK: - Type with delay (type-to-select pattern)

    public static func typeWithDelay(text: String, intervalMs: Int = 30) throws {
        for ch in text {
            let s = String(ch)
            try type(text: s)
            usleep(useconds_t(intervalMs * 1000))
        }
    }

    // MARK: - Key repeat

    public static func keyRepeat(combo: String, count: Int) throws {
        for _ in 0..<count { try key(combo: combo) }
    }

    // MARK: - Magnify (pinch approximation)

    /// Approximated pinch / magnify via Option+scroll, which SwiftUI's
    /// `MagnificationGesture` and AppKit's pinch path both observe in many
    /// apps. Real two-finger pinch via private HID events is intentionally not
    /// in scope for v1 — the call below is a portable, public-API-only
    /// replacement that handles the common case.
    ///
    /// `delta` > 0 → zoom in, < 0 → zoom out.
    public static func magnify(at point: CGPoint, delta: Int32) throws {
        try move(to: point)
        usleep(5_000)
        guard let e = CGEvent(scrollWheelEvent2Source: source,
                              units: .pixel,
                              wheelCount: 1,
                              wheel1: delta,
                              wheel2: 0,
                              wheel3: 0) else {
            throw InjectError.eventCreateFailed("scrollWheelEvent (magnify)")
        }
        e.flags = [.maskAlternate]
        e.post(tap: .cgSessionEventTap)
    }

    // MARK: - Keyboard

    /// Type arbitrary text into the currently focused element. Uses the
    /// unicode string attribute of CGEvent so we avoid keycode mapping.
    public static func type(text: String) throws {
        let utf16 = Array(text.utf16)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
            throw InjectError.eventCreateFailed("keyboardEvent")
        }
        utf16.withUnsafeBufferPointer { buf in
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: buf.baseAddress)
        }
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    /// Post a keyboard shortcut. Accepts `"return"`, `"escape"`, `"tab"`, `"space"`,
    /// `"cmd+s"`, `"shift+cmd+n"`, etc.
    public static func key(combo: String) throws {
        let (flags, keyCode) = try parseCombo(combo)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) else {
            throw InjectError.eventCreateFailed("keyEvent for \(combo)")
        }
        down.flags = flags
        up.flags = flags
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    // MARK: - Private

    private static var source: CGEventSource? { CGEventSource(stateID: .hidSystemState) }

    /// Parses a combo like "cmd+shift+n" into CG flags + key code.
    private static func parseCombo(_ combo: String) throws -> (CGEventFlags, CGKeyCode) {
        let parts = combo.lowercased().split(separator: "+").map(String.init)
        var flags: CGEventFlags = []
        var keyName: String = ""
        for p in parts {
            switch p {
            case "cmd", "command", "⌘": flags.insert(.maskCommand)
            case "shift", "⇧": flags.insert(.maskShift)
            case "opt", "option", "alt", "⌥": flags.insert(.maskAlternate)
            case "ctrl", "control", "⌃": flags.insert(.maskControl)
            case "fn", "function": flags.insert(.maskSecondaryFn)
            default: keyName = p
            }
        }
        guard let code = keyCode(for: keyName) else { throw InjectError.unknownKey(keyName) }
        return (flags, code)
    }

    /// Map a handful of common key names to macOS virtual key codes.
    /// Letters and digits map through a lookup. Named keys are explicit.
    private static func keyCode(for name: String) -> CGKeyCode? {
        switch name {
        // Letters (lowercase)
        case "a": return 0x00
        case "s": return 0x01
        case "d": return 0x02
        case "f": return 0x03
        case "h": return 0x04
        case "g": return 0x05
        case "z": return 0x06
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        case "b": return 0x0B
        case "q": return 0x0C
        case "w": return 0x0D
        case "e": return 0x0E
        case "r": return 0x0F
        case "y": return 0x10
        case "t": return 0x11
        case "o": return 0x1F
        case "u": return 0x20
        case "i": return 0x22
        case "p": return 0x23
        case "l": return 0x25
        case "j": return 0x26
        case "k": return 0x28
        case "n": return 0x2D
        case "m": return 0x2E
        // Named
        case "return", "enter", "ret": return 0x24
        case "tab": return 0x30
        case "space", "spc": return 0x31
        case "delete", "backspace", "bs": return 0x33
        case "escape", "esc": return 0x35
        case "up", "uparrow": return 0x7E
        case "down", "downarrow": return 0x7D
        case "left", "leftarrow": return 0x7B
        case "right", "rightarrow": return 0x7C
        case "home": return 0x73
        case "end": return 0x77
        case "pageup": return 0x74
        case "pagedown": return 0x79
        default: return nil
        }
    }
}
