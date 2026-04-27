import Foundation

/// Pry's in-process harness. Linked into the target app under `#if DEBUG`.
///
/// Calling `PryHarness.start()` opens a passive Unix-socket server at
/// `/tmp/pry-<bundleID>.sock` and begins answering JSON-RPC queries from
/// `pry-mcp`. PryHarness never drives the UI — all clicks, typing, and event
/// injection happen out-of-process in `pry-mcp`.
///
/// Safe to call multiple times (idempotent). No-op in RELEASE builds when
/// gated behind `#if DEBUG`.
public enum PryHarness {
    public static let version = "0.1.0"

    private static let lock = NSLock()
    nonisolated(unsafe) private static var server: PrySocketServer?

    /// Start the harness. Idempotent.
    ///
    /// - Parameter bundleID: override for the socket naming; defaults to
    ///   `Bundle.main.bundleIdentifier` or `"unknown"` if none.
    public static func start(bundleID overrideID: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        guard server == nil else { return }

        let bundle = overrideID
            ?? Bundle.main.bundleIdentifier
            ?? ProcessInfo.processInfo.processName
        let path = socketPath(for: bundle)

        let s = PrySocketServer(socketPath: path, appBundle: bundle)
        do {
            try s.start()
            server = s
        } catch {
            // Non-fatal: we're in DEBUG builds. Log and continue so the host
            // app still runs normally.
            FileHandle.standardError.write(Data("[PryHarness] start failed: \(error)\n".utf8))
        }
    }

    /// Stop the harness. Usually unnecessary — the server dies with the process —
    /// but useful in tests and controlled shutdowns.
    public static func stop() {
        lock.lock()
        defer { lock.unlock() }
        server?.stop()
        server = nil
    }

    /// Socket path for a given bundle ID. Exposed for `pry-mcp` to use via
    /// the shared convention.
    public static func socketPath(for bundleID: String) -> String {
        "/tmp/pry-\(bundleID).sock"
    }
}
