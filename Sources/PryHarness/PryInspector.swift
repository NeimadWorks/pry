import Foundation

/// In-process shim that produces a textual dump of all registered ViewModels.
/// Complements out-of-process AX introspection in `pry-mcp`. Used by
/// `read_state` (no path) and the `dump_state` debug aid.
public enum PryInspector {

    @MainActor
    public static func dumpAllRegistered() -> [String: [String: any Sendable]] {
        var out: [String: [String: any Sendable]] = [:]
        for name in PryRegistry.shared.registeredNames() {
            if let snap = PryRegistry.shared.snapshot(of: name) {
                out[name] = snap
            }
        }
        return out
    }
}
