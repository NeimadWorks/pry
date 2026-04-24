import Foundation
import CoreGraphics
import PryWire
import PryHarness

/// The implementation of each pry_* MCP tool. Stateless: every call takes
/// `app` (bundle ID) and opens a short-lived harness connection.
///
/// On success, tools return a human-readable text payload. On error they
/// throw a `ToolError` that carries a `kind` string (stable) plus a message
/// and optional fix hint — mirrored into the MCP error envelope.
enum PryTools {

    enum ToolError: Error {
        case kinded(kind: String, message: String, fix: String? = nil)

        var kind: String {
            if case .kinded(let k, _, _) = self { return k }
            return "internal"
        }
        var message: String {
            if case .kinded(_, let m, _) = self { return m }
            return "\(self)"
        }
        var fix: String? {
            if case .kinded(_, _, let f) = self { return f }
            return nil
        }
    }

    // MARK: - Lifecycle

    /// `pry_launch` — launch by bundle ID (installed .app) or by executable path.
    struct LaunchInput: Codable {
        var app: String                 // bundle ID
        var executable_path: String?    // optional, for SwiftPM fixtures
        var args: [String]?
        var env: [String: String]?
    }
    struct LaunchOutput: Codable {
        var pid: Int
        var socket: String
        var harness_version: String
    }
    static func launch(_ input: LaunchInput) async throws -> LaunchOutput {
        let handle: AppDriver.Handle
        do {
            if let path = input.executable_path {
                handle = try AppDriver.launchByPath(
                    executablePath: path,
                    bundleID: input.app,
                    args: input.args ?? [],
                    env: input.env ?? [:]
                )
            } else {
                handle = try await AppDriver.launchByBundleID(
                    input.app,
                    args: input.args ?? [],
                    env: input.env ?? [:]
                )
            }
        } catch let e as AppDriver.DriverError {
            switch e {
            case .bundleNotFound: throw ToolError.kinded(kind: "app_not_found", message: e.description)
            case .executableNotFound: throw ToolError.kinded(kind: "app_not_found", message: e.description)
            case .harnessSocketTimeout: throw ToolError.kinded(
                kind: "harness_unreachable",
                message: e.description,
                fix: "Ensure the target app calls PryHarness.start() under #if DEBUG.")
            default: throw ToolError.kinded(kind: "internal", message: e.description)
            }
        }
        // Handshake with retry. The socket file exists after bind(), but the
        // listen() + accept loop spin-up can race our first connect — retry
        // briefly on ECONNREFUSED.
        let hello = try await handshakeWithRetry(socketPath: handle.socketPath, timeout: 2)
        return LaunchOutput(pid: Int(hello.pid), socket: handle.socketPath, harness_version: hello.harnessVersion)
    }

    private static func handshakeWithRetry(socketPath: String, timeout: TimeInterval) async throws -> PryWire.HelloResult {
        let deadline = Date().addingTimeInterval(timeout)
        var lastError: Error?
        while Date() < deadline {
            do {
                let client = try HarnessClient(connectingTo: socketPath)
                return try await client.hello(client: "pry-mcp", version: PryMCP.version)
            } catch {
                lastError = error
                try? await Task.sleep(nanoseconds: 50_000_000)
            }
        }
        if let e = lastError as? HarnessClient.ClientError {
            throw ToolError.kinded(kind: "harness_unreachable", message: e.description,
                                   fix: "Ensure the target app calls PryHarness.start() under #if DEBUG.")
        }
        throw ToolError.kinded(kind: "harness_unreachable", message: "harness handshake timed out at \(socketPath)")
    }

    /// `pry_terminate` — send SIGTERM to the target.
    struct TerminateInput: Codable { var app: String }
    struct TerminateOutput: Codable { var ok: Bool }
    static func terminate(_ input: TerminateInput) async throws -> TerminateOutput {
        // Best-effort: find PID via NSRunningApplication or via hello, then kill.
        if let handle = try? AppDriver.attach(bundleID: input.app) {
            AppDriver.terminate(handle)
            return TerminateOutput(ok: true)
        }
        return TerminateOutput(ok: false)
    }

    // MARK: - State

    struct StateInput: Codable {
        var app: String
        var viewmodel: String
        var path: String?
    }
    struct StateOutput: Codable {
        var value: PryWire.AnyCodable?
        var keys: [String: PryWire.AnyCodable]?
    }
    static func state(_ input: StateInput) async throws -> StateOutput {
        let client = try await harnessConnection(for: input.app)
        do {
            let result = try await client.readState(viewmodel: input.viewmodel, path: input.path)
            return StateOutput(value: result.value, keys: result.keys)
        } catch let e as HarnessClient.ClientError {
            throw Self.translate(e)
        }
    }

    // MARK: - Control

    struct TargetSpec: Codable {
        var id: String?
        var role: String?
        var label: String?
        var label_matches: String?
        var tree_path: String?
        var point: PointSpec?
    }
    struct PointSpec: Codable {
        var x: Double
        var y: Double
    }

    static func parseTarget(_ spec: TargetSpec) throws -> Target {
        if let id = spec.id { return .id(id) }
        if let role = spec.role, let label = spec.label { return .roleLabel(role: role, label: label) }
        if let label = spec.label { return .label(label) }
        if let lm = spec.label_matches { return .labelMatches(lm) }
        if let tp = spec.tree_path { return .treePath(tp) }
        if let p = spec.point { return .point(x: CGFloat(p.x), y: CGFloat(p.y)) }
        throw ToolError.kinded(kind: "invalid_params",
                               message: "target must specify one of: id, role+label, label, label_matches, tree_path, point")
    }

    struct ClickInput: Codable {
        var app: String
        var target: TargetSpec
    }
    struct ClickOutput: Codable {
        var resolved: ResolvedOutput
    }
    struct ResolvedOutput: Codable {
        var role: String
        var label: String?
        var id: String?
        var frame: [Double]?
    }

    static func click(_ input: ClickInput) async throws -> ClickOutput {
        let target = try parseTarget(input.target)
        let pid = try await harnessHello(app: input.app).pid
        let resolved: Resolved
        do {
            resolved = try ElementResolver.resolve(target: target, in: pid)
        } catch let e as ResolveError {
            throw Self.translate(e)
        }
        guard let frame = resolved.frame else {
            throw ToolError.kinded(kind: "resolution_empty",
                                   message: "resolved element has no frame")
        }
        try EventInjector.click(at: CGPoint(x: frame.midX, y: frame.midY))
        return ClickOutput(resolved: ResolvedOutput(
            role: resolved.role,
            label: resolved.label,
            id: resolved.identifier,
            frame: [frame.origin.x, frame.origin.y, frame.width, frame.height]
        ))
    }

    struct TypeInput: Codable {
        var app: String
        var text: String
    }
    struct TypeOutput: Codable { var chars_sent: Int }
    static func typeText(_ input: TypeInput) async throws -> TypeOutput {
        _ = try await harnessHello(app: input.app) // ensure harness is alive / AX trust checked
        try ElementResolver.requireTrust()
        try EventInjector.type(text: input.text)
        return TypeOutput(chars_sent: input.text.count)
    }

    struct KeyInput: Codable {
        var app: String
        var combo: String
    }
    struct KeyOutput: Codable { var ok: Bool }
    static func key(_ input: KeyInput) async throws -> KeyOutput {
        _ = try await harnessHello(app: input.app)
        try ElementResolver.requireTrust()
        try EventInjector.key(combo: input.combo)
        return KeyOutput(ok: true)
    }

    // MARK: - Helpers

    private static func harnessConnection(for bundle: String) async throws -> HarnessClient {
        let path = PryHarness.socketPath(for: bundle)
        do {
            let client = try HarnessClient(connectingTo: path)
            _ = try await client.hello(client: "pry-mcp", version: PryMCP.version)
            return client
        } catch let e as HarnessClient.ClientError {
            throw Self.translate(e)
        }
    }

    private static func harnessHello(app: String) async throws -> PryWire.HelloResult {
        let path = PryHarness.socketPath(for: app)
        let client = try HarnessClient(connectingTo: path)
        return try await client.hello(client: "pry-mcp", version: PryMCP.version)
    }

    static func translate(_ e: HarnessClient.ClientError) -> ToolError {
        switch e {
        case .connect:
            return .kinded(kind: "harness_unreachable",
                           message: e.description,
                           fix: "Launch the app first via pry_launch, or ensure PryHarness.start() is called.")
        case .rpcError(let err):
            let kind: String
            switch err.code {
            case PryWire.RPCError.viewmodelNotRegistered: kind = "viewmodel_not_registered"
            case PryWire.RPCError.pathNotFound: kind = "path_not_found"
            case PryWire.RPCError.methodNotFound: kind = "not_implemented"
            case PryWire.RPCError.invalidParams: kind = "invalid_params"
            default: kind = "internal"
            }
            return .kinded(kind: kind, message: err.message)
        default:
            return .kinded(kind: "internal", message: e.description)
        }
    }

    static func translate(_ e: ResolveError) -> ToolError {
        switch e {
        case .accessibilityNotTrusted:
            return .kinded(kind: "ax_permission_denied",
                           message: e.description,
                           fix: "System Settings → Privacy & Security → Accessibility")
        case .noMatch:
            return .kinded(kind: "resolution_empty", message: e.description)
        case .ambiguous:
            return .kinded(kind: "resolution_ambiguous", message: e.description,
                           fix: "Narrow the target via `id` (highest precedence) or add a `role:` constraint.")
        case .windowNotFound:
            return .kinded(kind: "window_not_found", message: e.description)
        }
    }
}

enum PryMCP {
    static let version = "0.1.0-dev"
}
