import Foundation
import ApplicationServices
import CoreGraphics

/// Out-of-process walker over an app's AX tree. Produces Sendable snapshot
/// nodes and human-readable YAML dumps for verdicts.
public struct AXNode: Sendable {
    public let role: String
    public let label: String?
    public let identifier: String?
    public let value: String?
    public let frame: [Double]?
    public let enabled: Bool
    public let focused: Bool
    public let children: [AXNode]
}

public enum AXTreeWalker {

    public static func snapshot(pid: pid_t, window: WindowFilter? = nil) -> AXNode {
        let app = AXUIElementCreateApplication(pid)
        // If a window filter is provided, wrap matching windows only.
        if let filter = window,
           let windows = axAttr(app, kAXWindowsAttribute) as? [AXUIElement] {
            let picked = windows.filter { matches($0, filter) }
            let children = picked.map { build($0) }
            return AXNode(role: "AXApplication", label: nil, identifier: nil, value: nil,
                          frame: nil, enabled: true, focused: false, children: children)
        }
        return build(app)
    }

    public static func resolveWindow(pid: pid_t, filter: WindowFilter?) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        guard let filter else {
            return (axAttr(app, kAXWindowsAttribute) as? [AXUIElement])?.first
        }
        let windows = (axAttr(app, kAXWindowsAttribute) as? [AXUIElement]) ?? []
        return windows.first(where: { matches($0, filter) })
    }

    public static func renderYAML(_ node: AXNode, indent: Int = 0) -> String {
        var out = ""
        let pad = String(repeating: "  ", count: indent)
        var header = "\(pad)- \(node.role)"
        if let id = node.identifier { header += " id=\"\(id)\"" }
        if let l = node.label { header += " label=\"\(l)\"" }
        if let v = node.value, v.count < 80 { header += " value=\"\(v)\"" }
        if let f = node.frame {
            header += String(format: " frame=(%.0f,%.0f,%.0f,%.0f)", f[0], f[1], f[2], f[3])
        }
        if !node.enabled { header += " enabled=false" }
        if node.focused { header += " focused=true" }
        out += header + "\n"
        for c in node.children {
            out += renderYAML(c, indent: indent + 1)
        }
        return out
    }

    /// Trims a full tree to a small region around a subset of elements.
    /// Used to produce compact AX snippets for verdict failure sections.
    public static func truncated(_ tree: AXNode, maxDepth: Int = 4, maxChildren: Int = 6) -> AXNode {
        truncate(tree, depth: 0, maxDepth: maxDepth, maxChildren: maxChildren)
    }

    private static func truncate(_ node: AXNode, depth: Int, maxDepth: Int, maxChildren: Int) -> AXNode {
        let kids: [AXNode]
        if depth >= maxDepth {
            kids = []
        } else {
            kids = Array(node.children.prefix(maxChildren)).map {
                truncate($0, depth: depth + 1, maxDepth: maxDepth, maxChildren: maxChildren)
            }
        }
        return AXNode(role: node.role, label: node.label, identifier: node.identifier,
                      value: node.value, frame: node.frame, enabled: node.enabled,
                      focused: node.focused, children: kids)
    }

    // MARK: -

    private static func build(_ el: AXUIElement) -> AXNode {
        let role = (axAttr(el, kAXRoleAttribute) as? String) ?? "?"
        let label = (axAttr(el, kAXTitleAttribute) as? String)
            ?? (axAttr(el, kAXDescriptionAttribute) as? String)
        let identifier = axAttr(el, "AXIdentifier") as? String
        let value: String? = {
            if let s = axAttr(el, kAXValueAttribute) as? String { return s }
            if let n = axAttr(el, kAXValueAttribute) as? NSNumber { return n.stringValue }
            return nil
        }()
        let frame: [Double]? = {
            guard let pos = axAttr(el, kAXPositionAttribute),
                  let size = axAttr(el, kAXSizeAttribute) else { return nil }
            var origin = CGPoint.zero, sz = CGSize.zero
            AXValueGetValue(pos as! AXValue, .cgPoint, &origin)
            AXValueGetValue(size as! AXValue, .cgSize, &sz)
            return [Double(origin.x), Double(origin.y), Double(sz.width), Double(sz.height)]
        }()
        let enabled = (axAttr(el, kAXEnabledAttribute) as? Bool) ?? true
        let focused = (axAttr(el, kAXFocusedAttribute) as? Bool) ?? false
        let kidEls = axAttr(el, kAXChildrenAttribute) as? [AXUIElement] ?? []
        let children = kidEls.map { build($0) }
        return AXNode(role: role, label: label, identifier: identifier, value: value,
                      frame: frame, enabled: enabled, focused: focused, children: children)
    }

    private static func axAttr(_ el: AXUIElement, _ attr: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(el, attr as CFString, &value) == .success ? value : nil
    }

    private static func matches(_ window: AXUIElement, _ filter: WindowFilter) -> Bool {
        let title = (axAttr(window, kAXTitleAttribute) as? String) ?? ""
        if let t = filter.title, t != title { return false }
        if let tm = filter.titleMatches {
            guard let re = try? NSRegularExpression(pattern: tm) else { return false }
            let range = NSRange(title.startIndex..., in: title)
            if re.firstMatch(in: title, range: range) == nil { return false }
        }
        return true
    }
}

public struct WindowFilter: Sendable {
    public var title: String?
    public var titleMatches: String?
    public init(title: String? = nil, titleMatches: String? = nil) {
        self.title = title
        self.titleMatches = titleMatches
    }
}
