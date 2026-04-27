import Foundation

/// Heuristic a11y audit on an AX tree snapshot. Reports issues a developer
/// almost always wants to fix: interactive elements without labels, buttons
/// without identifiers in apps where Pry expects them, etc.
public enum AccessibilityAudit {

    public struct Issue: Sendable {
        public enum Severity: String, Sendable { case error, warning, info }
        public let rule: String
        public let severity: Severity
        public let message: String
        public let path: String       // best-effort tree path: "Window > Group > Button"
    }

    public static func audit(_ tree: AXNode) -> [Issue] {
        var issues: [Issue] = []
        walk(tree, path: [], issues: &issues)
        return issues
    }

    private static func walk(_ node: AXNode, path: [String], issues: inout [Issue]) {
        let name = node.identifier.map { "\(node.role)#\($0)" }
            ?? node.label.map { "\(node.role)[\"\($0)\"]" }
            ?? node.role
        let here = path + [name]
        let pathString = here.joined(separator: " > ")

        // Rule 1: interactive elements without label.
        let interactive = ["AXButton", "AXCheckBox", "AXRadioButton", "AXLink", "AXMenuItem"]
        if interactive.contains(node.role), node.label == nil || node.label == "" {
            issues.append(Issue(
                rule: "missing_label",
                severity: .error,
                message: "interactive \(node.role) has no label",
                path: pathString
            ))
        }

        // Rule 2: text fields without identifier — VoiceOver users will struggle.
        if node.role == "AXTextField", node.identifier == nil {
            issues.append(Issue(
                rule: "textfield_no_identifier",
                severity: .warning,
                message: "AXTextField has no AXIdentifier — set .accessibilityIdentifier(...)",
                path: pathString
            ))
        }

        // Rule 3: zero-frame interactive elements.
        if interactive.contains(node.role), let f = node.frame, f.count == 4 {
            if f[2] < 1 || f[3] < 1 {
                issues.append(Issue(
                    rule: "zero_frame_interactive",
                    severity: .warning,
                    message: "interactive \(node.role) has zero frame; likely off-screen / hidden",
                    path: pathString
                ))
            }
        }

        // Rule 4: nested AXButton inside AXButton (common SwiftUI gotcha).
        if node.role == "AXButton", path.contains(where: { $0.hasPrefix("AXButton") }) {
            issues.append(Issue(
                rule: "nested_button",
                severity: .info,
                message: "AXButton nested inside another AXButton — VoiceOver collapses these",
                path: pathString
            ))
        }

        for c in node.children { walk(c, path: here, issues: &issues) }
    }

    public static func render(_ issues: [Issue]) -> String {
        if issues.isEmpty { return "Accessibility audit: no issues found.\n" }
        var out = "Accessibility audit: \(issues.count) issue\(issues.count == 1 ? "" : "s")\n\n"
        for i in issues {
            out += "- [\(i.severity.rawValue.uppercased())] \(i.rule): \(i.message)\n  at: \(i.path)\n"
        }
        return out
    }
}
