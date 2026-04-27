import Foundation
import PryWire

/// Central registry for `PryInspectable` ViewModels.
///
/// Register each VM once — typically in a `.task` modifier or at `init` time.
/// The registry holds a weak reference to the instance, so deallocation is safe.
@MainActor
public final class PryRegistry {
    public static let shared = PryRegistry()

    private var snapshots: [String: () -> [String: any Sendable]] = [:]
    private var lastSnapshots: [String: [String: String]] = [:]
    private var subscriptions: [String: PryStateSubscription] = [:]

    private init() {}

    /// Register a `PryInspectable` instance. If a VM with the same `pryName`
    /// was registered previously, the new registration replaces it.
    /// If the VM also conforms to `PryStateBroadcaster`, the registry hooks
    /// its push channel and rebroadcasts diffs over `PryEventBus`.
    public func register<T: PryInspectable>(_ instance: T) {
        let name = T.pryName
        snapshots[name] = { [weak instance] in
            instance?.prySnapshot() ?? [:]
        }
        lastSnapshots[name] = stringifySnapshot(instance.prySnapshot())

        if let broadcaster = instance as? any PryStateBroadcaster {
            subscriptions[name]?.cancel()
            subscriptions[name] = broadcaster.prySubscribeStateChanges { [weak self] in
                guard let self else { return }
                self.captureAndDiff(name: name)
            }
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

    /// Force a diff & publish for `name`. Useful for VMs that don't conform to
    /// PryStateBroadcaster — call this after a known mutation point.
    public func notifyChange(_ name: String) {
        captureAndDiff(name: name)
    }

    private func captureAndDiff(name: String) {
        guard let snap = snapshots[name]?() else { return }
        let stringified = stringifySnapshot(snap)
        let prev = lastSnapshots[name] ?? [:]
        var changes: [(key: String, oldValue: String?, newValue: String)] = []
        for (k, v) in stringified where prev[k] != v {
            changes.append((k, prev[k], v))
        }
        lastSnapshots[name] = stringified
        guard !changes.isEmpty else { return }
        for c in changes {
            let payload: [String: any Sendable] = [
                "viewmodel": name,
                "key": c.key,
                "old": c.oldValue ?? "<nil>",
                "new": c.newValue,
            ]
            PryEventBus.shared.publish(
                kind: .stateChanged,
                data: PryWire.AnyCodable(payload as any Sendable)
            )
        }
    }

    private func stringifySnapshot(_ s: [String: any Sendable]) -> [String: String] {
        var out: [String: String] = [:]
        for (k, v) in s { out[k] = "\(v)" }
        return out
    }
}
