import Foundation

/// Central registry for `PryInspectable` ViewModels.
///
/// Register each VM once — typically in a `.task` modifier or at `init` time.
/// The registry holds a weak reference to the instance, so deallocation is safe.
@MainActor
public final class PryRegistry {
    public static let shared = PryRegistry()

    private var snapshots: [String: () -> [String: any Sendable]] = [:]

    private init() {}

    /// Register a `PryInspectable` instance. If a VM with the same `pryName`
    /// was registered previously, the new registration replaces it.
    public func register<T: PryInspectable>(_ instance: T) {
        let name = T.pryName
        snapshots[name] = { [weak instance] in
            instance?.prySnapshot() ?? [:]
        }
    }

    /// Remove a registration. Not usually needed — weak refs handle dealloc —
    /// but useful in tests that rebuild state.
    public func unregister(name: String) {
        snapshots.removeValue(forKey: name)
    }

    /// Current snapshot of the VM named `name`, or `nil` if none registered.
    public func snapshot(of name: String) -> [String: any Sendable]? {
        snapshots[name]?()
    }

    /// All registered VM names.
    public func registeredNames() -> [String] {
        Array(snapshots.keys).sorted()
    }
}
