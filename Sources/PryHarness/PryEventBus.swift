import Foundation
import PryWire

/// Internal event bus used by `PrySocketServer` to push notifications to
/// subscribed clients. See [ADR-008].
///
/// Producers (registry, AX observer, etc.) call `publish(_:)` from any actor.
/// The bus serializes delivery on its own queue and broadcasts to all
/// matching subscribers.
public final class PryEventBus: @unchecked Sendable {
    public static let shared = PryEventBus()

    private let lock = NSLock()
    private var subscribers: [String: Subscriber] = [:]
    private struct Subscriber {
        let id: String
        let kinds: Set<PryWire.NotificationKind>
        let deliver: @Sendable (PryWire.NotificationParams) -> Void
    }

    private init() {}

    public func subscribe(kinds: [PryWire.NotificationKind],
                          deliver: @escaping @Sendable (PryWire.NotificationParams) -> Void) -> String {
        lock.lock(); defer { lock.unlock() }
        let id = UUID().uuidString
        subscribers[id] = Subscriber(id: id, kinds: Set(kinds), deliver: deliver)
        return id
    }

    public func unsubscribe(_ id: String) {
        lock.lock(); defer { lock.unlock() }
        subscribers.removeValue(forKey: id)
    }

    public func publish(kind: PryWire.NotificationKind, data: PryWire.AnyCodable) {
        lock.lock()
        let subs = subscribers.values.filter { $0.kinds.isEmpty || $0.kinds.contains(kind) }
        lock.unlock()
        let params = PryWire.NotificationParams(kind: kind, data: data)
        for s in subs { s.deliver(params) }
    }
}
