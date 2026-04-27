import Foundation

/// Virtual clock that the host app opts into.
///
/// In RELEASE the clock delegates to the system. In DEBUG the test runner can
/// pause, set, or advance it. Apps replace `Date()` / `Timer` / `Task.sleep`
/// usages with the clock equivalents to make their time-dependent code
/// deterministic in tests.
///
/// Adoption is incremental — any code path still using `Date()` directly stays
/// real-time. See [ADR-007].
public final class PryClock: @unchecked Sendable {
    public static let shared = PryClock()

    private let lock = NSLock()
    private var _now: Date
    private var _paused: Bool = false
    private var pending: [Scheduled] = []
    private var nextID: Int = 0

    private struct Scheduled {
        let id: Int
        var deadline: Date
        let work: @Sendable () -> Void
    }

    private init() {
        self._now = Date()
    }

    // MARK: - Public read

    public var now: Date {
        lock.lock(); defer { lock.unlock() }
        return _paused ? _now : Date().addingTimeInterval(_now.timeIntervalSince(Date()))
    }

    public var isPaused: Bool {
        lock.lock(); defer { lock.unlock() }
        return _paused
    }

    // MARK: - Public scheduling (use these instead of Timer / asyncAfter)

    /// Schedule `work` to run after `seconds` of *clock* time.
    @discardableResult
    public func after(_ seconds: TimeInterval, _ work: @escaping @Sendable () -> Void) -> Token {
        lock.lock(); defer { lock.unlock() }
        nextID += 1
        let id = nextID
        let deadline = effectiveNowLocked().addingTimeInterval(seconds)
        pending.append(Scheduled(id: id, deadline: deadline, work: work))
        // If the clock isn't paused, we still rely on a system timer to keep it accurate
        // when no one is calling `advance(...)`. Schedule a real DispatchQueue check.
        if !_paused {
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [weak self] in
                self?.fire(id: id)
            }
        }
        return Token(id: id)
    }

    /// Sleep for `seconds` of clock time. When the clock is paused, this only
    /// returns once the clock has been advanced enough by the runner.
    public func sleep(_ seconds: TimeInterval) async {
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.after(seconds) {
                cont.resume()
            }
        }
    }

    // MARK: - Test-runner control

    /// Set the absolute clock value. Optionally pause/resume.
    /// Returns the number of scheduled callbacks that fired (deadline ≤ new time).
    @discardableResult
    public func set(to date: Date, paused: Bool? = nil) -> Int {
        lock.lock()
        _now = date
        if let paused { _paused = paused }
        let due = pending.filter { $0.deadline <= date }
        pending.removeAll { $0.deadline <= date }
        lock.unlock()
        for s in due.sorted(by: { $0.deadline < $1.deadline }) { s.work() }
        return due.count
    }

    /// Advance the clock by `seconds`. Fires every callback whose deadline
    /// falls within the new window, in chronological order.
    @discardableResult
    public func advance(by seconds: TimeInterval) -> Int {
        lock.lock()
        _now = effectiveNowLocked().addingTimeInterval(seconds)
        let due = pending.filter { $0.deadline <= _now }
        pending.removeAll { $0.deadline <= _now }
        let target = _now
        lock.unlock()
        for s in due.sorted(by: { $0.deadline < $1.deadline }) { s.work() }
        _ = target
        return due.count
    }

    public func pause() {
        lock.lock(); defer { lock.unlock() }
        _now = effectiveNowLocked()
        _paused = true
    }

    public func resume() {
        lock.lock(); defer { lock.unlock() }
        _paused = false
    }

    // MARK: - Cancellation

    public struct Token: Sendable {
        public let id: Int
    }

    public func cancel(_ token: Token) {
        lock.lock(); defer { lock.unlock() }
        pending.removeAll { $0.id == token.id }
    }

    // MARK: - Internals

    private func effectiveNowLocked() -> Date {
        // Caller holds lock.
        if _paused { return _now }
        // When unpaused, _now is treated as a "frozen reference at last set/advance"
        // and the wall clock advances normally on top.
        return _now
    }

    private func fire(id: Int) {
        lock.lock()
        guard let idx = pending.firstIndex(where: { $0.id == id }) else { lock.unlock(); return }
        let s = pending.remove(at: idx)
        lock.unlock()
        s.work()
    }
}
