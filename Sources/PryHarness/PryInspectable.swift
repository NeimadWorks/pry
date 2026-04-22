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
