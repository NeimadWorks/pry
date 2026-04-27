import Foundation
import AppKit
import ApplicationServices
import CoreGraphics

/// Out-of-process AX target resolution. The `Target` cases mirror the spec
/// grammar from `docs/design/spec-format.md §4`.
public enum Target: Sendable {
    case id(String)
    case roleLabel(role: String, label: String)
    case label(String)
    case labelMatches(String)
    case treePath(String)
    case point(x: CGFloat, y: CGFloat)
}

public struct Resolved: Sendable {
    public let element: AXUIElementWrapper
    public let frame: CGRect?
    public let role: String
    public let label: String?
    public let identifier: String?
}

/// Sendable wrapper around AXUIElement (which is CFTypeRef).
public struct AXUIElementWrapper: @unchecked Sendable {
    public let element: AXUIElement
}

public enum ResolveError: Error, CustomStringConvertible {
    case accessibilityNotTrusted
    case windowNotFound
    case noMatch(Target)
    case ambiguous(Target, candidates: [String])

    public var description: String {
        switch self {
        case .accessibilityNotTrusted:
            return "pry-mcp is not trusted for Accessibility. Grant in System Settings → Privacy & Security → Accessibility, then relaunch the parent process."
        case .windowNotFound:
            return "no window in target app"
        case .noMatch(let t):
            return "no AX element matches target: \(t)"
        case .ambiguous(let t, let cands):
            return "target \(t) is ambiguous (\(cands.count) matches):\n  - " + cands.joined(separator: "\n  - ")
        }
    }
}

public enum ElementResolver {

    public static func requireTrust() throws {
        guard AXIsProcessTrusted() else { throw ResolveError.accessibilityNotTrusted }
    }

    /// Resolves a target to exactly one AX element in the given app. Multiple matches
    /// for a same-precedence form is an error (the resolver never silent-picks the first).
    public static func resolve(target: Target, in pid: pid_t) throws -> Resolved {
        try requireTrust()
        let app = AXUIElementCreateApplication(pid)

        // Collect candidates; their set depends on the target form.
        var candidates: [AXUIElement] = []

        switch target {
        case .point(let x, let y):
            // Direct hit-test via AXUIElementCopyElementAtPosition.
            var el: AXUIElement?
            let err = AXUIElementCopyElementAtPosition(app, Float(x), Float(y), &el)
            guard err == .success, let el else { throw ResolveError.noMatch(target) }
            return Resolved(element: AXUIElementWrapper(element: el),
                            frame: axFrame(el),
                            role: axString(el, kAXRoleAttribute) ?? "?",
                            label: axString(el, kAXTitleAttribute),
                            identifier: axString(el, "AXIdentifier"))

        case .id, .roleLabel, .label, .labelMatches, .treePath:
            walk(app) { el in
                if matches(el, target) { candidates.append(el) }
            }
        }

        if candidates.isEmpty { throw ResolveError.noMatch(target) }
        if candidates.count > 1 {
            let descs = candidates.map { describe($0) }
            throw ResolveError.ambiguous(target, candidates: descs)
        }
        let el = candidates[0]
        return Resolved(element: AXUIElementWrapper(element: el),
                        frame: axFrame(el),
                        role: axString(el, kAXRoleAttribute) ?? "?",
                        label: axString(el, kAXTitleAttribute),
                        identifier: axString(el, "AXIdentifier"))
    }

    // MARK: - Matching

    private static func matches(_ el: AXUIElement, _ target: Target) -> Bool {
        switch target {
        case .id(let id):
            return axString(el, "AXIdentifier") == id
        case .roleLabel(let role, let label):
            return axString(el, kAXRoleAttribute) == role && anyLabel(el) == label
        case .label(let label):
            return anyLabel(el) == label
        case .labelMatches(let pattern):
            guard let l = anyLabel(el) else { return false }
            return (try? NSRegularExpression(pattern: pattern)
                .firstMatch(in: l, range: NSRange(l.startIndex..., in: l))) != nil
        case .treePath:
            return false // not implemented in v1
        case .point:
            return false
        }
    }

    private static func anyLabel(_ el: AXUIElement) -> String? {
        axString(el, kAXTitleAttribute)
            ?? axString(el, kAXDescriptionAttribute)
            ?? axString(el, "AXValueDescription")
    }

    // MARK: - AX helpers

    private static func walk(_ el: AXUIElement, visit: (AXUIElement) -> Void) {
        visit(el)
        guard let children = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] else { return }
        for c in children { walk(c, visit: visit) }
    }

    private static func axAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(el, attr as CFString, &value)
        return err == .success ? value : nil
    }

    private static func axString(_ el: AXUIElement, _ attr: String) -> String? {
        axAttr(el, attr) as? String
    }

    public static func axFrame(_ el: AXUIElement) -> CGRect? {
        guard let pos = axAttr(el, kAXPositionAttribute),
              let size = axAttr(el, kAXSizeAttribute) else { return nil }
        var origin = CGPoint.zero
        var sz = CGSize.zero
        AXValueGetValue(pos as! AXValue, .cgPoint, &origin)
        AXValueGetValue(size as! AXValue, .cgSize, &sz)
        return CGRect(origin: origin, size: sz)
    }

    private static func describe(_ el: AXUIElement) -> String {
        let role = axString(el, kAXRoleAttribute) ?? "?"
        let id = axString(el, "AXIdentifier").map { "id=\"\($0)\"" } ?? ""
        let label = anyLabel(el).map { "label=\"\($0)\"" } ?? ""
        let frame = axFrame(el).map { "frame=(\(Int($0.origin.x)),\(Int($0.origin.y)),\(Int($0.width)),\(Int($0.height)))" } ?? ""
        return [role, id, label, frame].filter { !$0.isEmpty }.joined(separator: " ")
    }
}
