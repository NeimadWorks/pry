import Foundation
import AppKit
import Darwin
import PryHarness

/// Launch / terminate / attach to the target app.
///
/// Two launch modes:
///  - `launchByPath` — direct executable, used for SwiftPM-built fixtures like DemoApp.
///  - `launchByBundleID` — via `NSWorkspace`, used for .app bundles installed on disk.
///
/// Either way, after launch we wait for the harness's Unix socket to appear,
/// proving that `PryHarness.start()` ran in the target process.
enum AppDriver {
    enum DriverError: Error, CustomStringConvertible {
        case executableNotFound(String)
        case bundleNotFound(String)
        case launchFailed(String)
        case harnessSocketTimeout(path: String, elapsed: TimeInterval)
        case alreadyRunning(pid: pid_t)

        var description: String {
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

    struct Handle {
        let pid: pid_t
        let bundleID: String
        let socketPath: String
        /// Only present when launched via `launchByPath`. `nil` for bundle-ID launches.
        fileprivate let process: Process?
    }

    // MARK: - Launch

    static func launchByPath(executablePath: String,
                             bundleID: String,
                             args: [String] = [],
                             env: [String: String] = [:],
                             socketTimeout: TimeInterval = 5) throws -> Handle {
        let url = URL(fileURLWithPath: executablePath)
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw DriverError.executableNotFound(url.path)
        }

        // Unlink any stale socket from a prior run — the new DemoApp process will
        // create a fresh one in its `PryHarness.start()`. Without this, runs of
        // multiple specs in a row race on `waitForSocket` hitting the leftover
        // inode before the new process has rebound.
        unlink(PryHarness.socketPath(for: bundleID))

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
        return Handle(pid: p.processIdentifier, bundleID: bundleID, socketPath: socket, process: p)
    }

    static func launchByBundleID(_ bundleID: String,
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
        return Handle(pid: running.processIdentifier, bundleID: bundleID, socketPath: socket, process: nil)
    }

    /// Attach to a running app by bundle ID. The harness socket must already be live.
    static func attach(bundleID: String, timeout: TimeInterval = 1) throws -> Handle {
        let socket = PryHarness.socketPath(for: bundleID)
        try waitForSocket(path: socket, timeout: timeout)

        // Best-effort PID lookup via NSRunningApplication (same-user apps only).
        let pid: pid_t = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier ?? 0
        return Handle(pid: pid, bundleID: bundleID, socketPath: socket, process: nil)
    }

    // MARK: - Terminate

    static func terminate(_ handle: Handle, timeout: TimeInterval = 3) {
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

    static func waitForSocket(path: String, timeout: TimeInterval) throws {
        let start = Date()
        let deadline = start.addingTimeInterval(timeout)
        while Date() < deadline {
            if FileManager.default.fileExists(atPath: path) { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
        throw DriverError.harnessSocketTimeout(path: path, elapsed: Date().timeIntervalSince(start))
    }
}
