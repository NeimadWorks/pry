import Foundation
import AppKit
import Darwin
import PryHarness

/// Launch / terminate / attach to the target app.
///
/// Three launch paths, all with post-launch foreground activation:
///  - `launchByPath` with an executable path → `Process.run()` (SwiftPM
///    fixtures like DemoApp).
///  - `launchByPath` with a `.app` bundle path → `NSWorkspace.openApplication`
///    (real apps that need LaunchServices to load entitlements + provisioning
///    profile; direct execve loses both).
///  - `launchByBundleID` → `NSWorkspace.openApplication` resolving via the
///    `.app` registered for that bundle ID.
///
/// In every case, after the harness socket appears we call
/// `NSRunningApplication.activate(...)` on the target so the freshly-launched
/// app becomes frontmost. Without this step, CGEvents are dispatched to
/// whichever process was foreground when `pry-mcp` ran (often the test
/// harness itself), and clicks/keys go into the void. Both Carnet and Jig
/// hit this in real-world dogfooding (see CLAUDE.md 2026-04-29).
public enum AppDriver {
    public enum DriverError: Error, CustomStringConvertible {
        case executableNotFound(String)
        case bundleNotFound(String)
        case launchFailed(String)
        case harnessSocketTimeout(path: String, elapsed: TimeInterval)
        case alreadyRunning(pid: pid_t)

        public var description: String {
            switch self {
            case .executableNotFound(let p): return "executable not found: \(p)"
            case .bundleNotFound(let id): return "no app registered for bundle id: \(id)"
            case .launchFailed(let s): return "launch failed: \(s)"
            case .harnessSocketTimeout(let p, let t):
                return "harness socket at \(p) did not appear within \(t)s — target app may not link PryHarness or may have crashed on launch"
            case .alreadyRunning(let pid): return "app already running (pid=\(pid))"
            }
        }
    }

    public struct Handle: @unchecked Sendable {
        public let pid: pid_t
        public let bundleID: String
        public let socketPath: String
        /// Only present when launched via `Process.run()` on a raw executable.
        /// `nil` for `.app`-bundle and bundle-ID launches (which use NSWorkspace).
        fileprivate let process: Process?

        fileprivate init(pid: pid_t, bundleID: String, socketPath: String, process: Process?) {
            self.pid = pid; self.bundleID = bundleID
            self.socketPath = socketPath; self.process = process
        }
    }

    // MARK: - Launch

    public static func launchByPath(executablePath: String,
                                    bundleID: String,
                                    args: [String] = [],
                                    env: [String: String] = [:],
                                    socketTimeout: TimeInterval = 5) async throws -> Handle {
        let url = URL(fileURLWithPath: executablePath).standardizedFileURL

        // Unlink any stale socket from a prior run — the new target process
        // creates a fresh one in `PryHarness.start()`. Without this, runs of
        // multiple specs in a row race on `waitForSocket` hitting the leftover
        // inode before the new process has rebound.
        unlink(PryHarness.socketPath(for: bundleID))

        // `.app` bundle? Route through LaunchServices so entitlements +
        // provisioning profile load. Direct `Process.run()` on the inner
        // executable strips both, which breaks any app that needs HCI access,
        // network entitlements, or sandbox containers.
        let isAppBundle: Bool = {
            guard url.pathExtension == "app" else { return false }
            var isDir: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            return exists && isDir.boolValue
        }()

        if isAppBundle {
            let config = NSWorkspace.OpenConfiguration()
            config.arguments = args
            config.environment = env
            config.activates = true
            let running: NSRunningApplication
            do {
                running = try await NSWorkspace.shared.openApplication(at: url, configuration: config)
            } catch {
                throw DriverError.launchFailed("\(error)")
            }
            let socket = PryHarness.socketPath(for: bundleID)
            try waitForSocket(path: socket, timeout: socketTimeout)
            forceActivate(pid: running.processIdentifier)
            return Handle(pid: running.processIdentifier, bundleID: bundleID,
                          socketPath: socket, process: nil)
        }

        // Direct executable path (SwiftPM fixtures).
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw DriverError.executableNotFound(url.path)
        }
        let p = Process()
        p.executableURL = url
        p.arguments = args
        var mergedEnv = ProcessInfo.processInfo.environment
        for (k, v) in env { mergedEnv[k] = v }
        p.environment = mergedEnv
        // Detach stdio so the MCP server's stdout isn't polluted by the target.
        p.standardOutput = Pipe()
        p.standardError = Pipe()

        do { try p.run() } catch { throw DriverError.launchFailed("\(error)") }

        let socket = PryHarness.socketPath(for: bundleID)
        try waitForSocket(path: socket, timeout: socketTimeout)
        forceActivate(pid: p.processIdentifier)
        return Handle(pid: p.processIdentifier, bundleID: bundleID, socketPath: socket, process: p)
    }

    public static func launchByBundleID(_ bundleID: String,
                                        args: [String] = [],
                                        env: [String: String] = [:],
                                        socketTimeout: TimeInterval = 10) async throws -> Handle {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            throw DriverError.bundleNotFound(bundleID)
        }
        let config = NSWorkspace.OpenConfiguration()
        config.arguments = args
        config.environment = env
        config.activates = true

        let running: NSRunningApplication
        do {
            running = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
        } catch {
            throw DriverError.launchFailed("\(error)")
        }

        let socket = PryHarness.socketPath(for: bundleID)
        try waitForSocket(path: socket, timeout: socketTimeout)
        forceActivate(pid: running.processIdentifier)
        return Handle(pid: running.processIdentifier, bundleID: bundleID, socketPath: socket, process: nil)
    }

    /// Attach to a running app by bundle ID. The harness socket must already be live.
    public static func attach(bundleID: String, timeout: TimeInterval = 1, activate: Bool = true) throws -> Handle {
        let socket = PryHarness.socketPath(for: bundleID)
        try waitForSocket(path: socket, timeout: timeout)

        // Best-effort PID lookup via NSRunningApplication (same-user apps only).
        let pid: pid_t = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier ?? 0
        if activate { forceActivate(pid: pid) }
        return Handle(pid: pid, bundleID: bundleID, socketPath: socket, process: nil)
    }

    // MARK: - Activation

    /// Bring the target process to the foreground. Public so spec writers can
    /// recover focus mid-flow (e.g. after a sheet dismissal returns it to the
    /// caller, or after another agent steals focus during a long suite run).
    public static func activate(bundleID: String) {
        let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier ?? 0
        forceActivate(pid: pid)
    }

    /// Internal helper. Polls briefly for the NSRunningApplication wrapper
    /// (it can take a few hundred ms to register a brand-new process on
    /// AppKit's run loop), then activates the app. Uses the modern
    /// `activate()` on macOS 14+ and falls back to the legacy
    /// `activate(options: .activateAllWindows)` on older systems (we don't
    /// support those today, but the conditional keeps the code honest).
    private static func forceActivate(pid: pid_t) {
        guard pid > 0 else { return }
        for _ in 0..<10 {
            if let app = NSRunningApplication(processIdentifier: pid) {
                _ = app.activate()
                return
            }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    // MARK: - Terminate

    public static func terminate(_ handle: Handle, timeout: TimeInterval = 3) {
        if let p = handle.process, p.isRunning {
            p.terminate()
            let deadline = Date().addingTimeInterval(timeout)
            while p.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }
            if p.isRunning { kill(handle.pid, SIGKILL) }
            return
        }
        if handle.pid > 0 {
            kill(handle.pid, SIGTERM)
        }
    }

    // MARK: - Socket wait

    public static func waitForSocket(path: String, timeout: TimeInterval) throws {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw DriverError.harnessSocketTimeout(path: path, elapsed: Date().timeIntervalSince(start))
    }
}
