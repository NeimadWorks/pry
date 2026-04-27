import Foundation

/// A ViewModel that opts into Pry's state introspection.
///
/// Implementations return a flat dictionary keyed by stable string paths
/// (e.g. `"documents.count"`, `"selection.id"`). Values must be JSON-friendly
/// (`Int`, `Double`, `Bool`, `String`, or nested `[String: any Sendable]` /
/// `[any Sendable]`) — the wire layer coerces anything else via
/// `String(describing:)`.
///
/// Conformance is `@MainActor`-bound so SwiftUI `ObservableObject` VMs can
/// read their own state without actor hopping.
@MainActor
public protocol PryInspectable: AnyObject {
    /// Stable name used in test specs (`assert_state: { viewmodel: <pryName>, ... }`).
    /// Defaults to the type name.
    static var pryName: String { get }

    /// Returns the current snapshot of exposed state.
    func prySnapshot() -> [String: any Sendable]
}

public extension PryInspectable {
    static var pryName: String { String(describing: Self.self) }
}

/// Optional conformance: VMs that adopt this can push state-change
/// notifications to subscribers without requiring polling.
///
/// The closure passed in is called on the main actor. Pass it the diff between
/// the previous snapshot and the new one (or just the new full snapshot — the
/// harness diffs internally).
@MainActor
public protocol PryStateBroadcaster: PryInspectable {
    /// Called by the registry to start observing changes. Implementations
    /// should call `notify()` whenever any prySnapshot key value changes.
    /// Return a cancellation handle.
    func prySubscribeStateChanges(_ notify: @escaping @MainActor () -> Void) -> PryStateSubscription
}

public protocol PryStateSubscription {
    func cancel()
}
