import Foundation

/// Shared wire types for the PryHarness ↔ pry-mcp Unix-socket JSON-RPC protocol.
///
/// This module contains **no logic** — only Codable types. Both sides of the socket
/// import it so the contract is enforced at compile time.
///
/// Transport framing is documented in `docs/api/PryWire.md`:
/// 4-byte big-endian frame length, followed by the UTF-8 JSON payload.
public enum PryWire {}

// MARK: - JSON-RPC envelope

extension PryWire {
    public struct Request<Params: Codable & Sendable>: Codable, Sendable {
        public var jsonrpc: String
        public var id: Int
        public var method: String
        public var params: Params

        public init(id: Int, method: String, params: Params) {
            self.jsonrpc = "2.0"
            self.id = id
            self.method = method
            self.params = params
        }
    }

    public struct Response<Result: Codable & Sendable>: Codable, Sendable {
        public var jsonrpc: String
        public var id: Int
        public var result: Result?
        public var error: RPCError?

        public init(id: Int, result: Result) {
            self.jsonrpc = "2.0"
            self.id = id
            self.result = result
            self.error = nil
        }

        public init(id: Int, error: RPCError) {
            self.jsonrpc = "2.0"
            self.id = id
            self.result = nil
            self.error = error
        }
    }

    /// Raw envelope used by the dispatcher before we know which method was called.
    /// `params` and `result` are held as `AnyCodable` so the handler can re-decode
    /// into the method-specific type.
    public struct RawRequest: Codable, Sendable {
        public var jsonrpc: String
        public var id: Int
        public var method: String
        public var params: AnyCodable

        public init(id: Int, method: String, params: AnyCodable) {
            self.jsonrpc = "2.0"
            self.id = id
            self.method = method
            self.params = params
        }
    }

    public struct RawResponse: Codable, Sendable {
        public var jsonrpc: String
        public var id: Int
        public var result: AnyCodable?
        public var error: RPCError?

        public init(jsonrpc: String = "2.0", id: Int, result: AnyCodable? = nil, error: RPCError? = nil) {
            self.jsonrpc = jsonrpc
            self.id = id
            self.result = result
            self.error = error
        }
    }
}

// MARK: - Error

extension PryWire {
    public struct RPCError: Codable, Sendable, Error {
        public var code: Int
        public var message: String
        public var data: [String: AnyCodable]?

        public init(code: Int, message: String, data: [String: AnyCodable]? = nil) {
            self.code = code
            self.message = message
            self.data = data
        }

        // JSON-RPC 2.0 standard codes
        public static let parseError = -32700
        public static let invalidRequest = -32600
        public static let methodNotFound = -32601
        public static let invalidParams = -32602
        public static let internalError = -32603

        // Pry-specific codes (negative custom range per JSON-RPC spec)
        public static let viewmodelNotRegistered = -32001
        public static let pathNotFound = -32002
        public static let windowNotFound = -32003
        public static let snapshotFailed = -32004
        public static let logStoreUnavailable = -32005
    }
}

// MARK: - Method catalog

extension PryWire {
    public enum Method: String, Codable, Sendable, CaseIterable {
        case hello
        case inspectTree = "inspect_tree"
        case readState = "read_state"
        case readLogs = "read_logs"
        case snapshot
        case goodbye
        // Wave 1
        case clockGet = "clock_get"
        case clockSet = "clock_set"
        case clockAdvance = "clock_advance"
        case setAnimations = "set_animations"
        case subscribe = "subscribe"
        case unsubscribe = "unsubscribe"
        case readPasteboard = "read_pasteboard"
        case writePasteboard = "write_pasteboard"
    }

    /// Notification kind, sent over the socket without an `id`. Clients
    /// subscribe via `subscribe` and consume these.
    public enum NotificationKind: String, Codable, Sendable, CaseIterable {
        case stateChanged = "state_changed"
        case windowAppeared = "window_appeared"
        case windowDisappeared = "window_disappeared"
        case sheetAppeared = "sheet_appeared"
        case logEmitted = "log_emitted"
    }

    public struct Notification: Codable, Sendable {
        public var jsonrpc: String
        public var method: String                // "notify"
        public var params: NotificationParams

        public init(params: NotificationParams) {
            self.jsonrpc = "2.0"
            self.method = "notify"
            self.params = params
        }
    }

    public struct NotificationParams: Codable, Sendable {
        public var kind: String                  // NotificationKind raw
        public var data: AnyCodable

        public init(kind: NotificationKind, data: AnyCodable) {
            self.kind = kind.rawValue
            self.data = data
        }
    }
}

// MARK: - hello

extension PryWire {
    public struct HelloParams: Codable, Sendable {
        public var client: String
        public var version: String
        public init(client: String, version: String) {
            self.client = client
            self.version = version
        }
    }

    public struct HelloResult: Codable, Sendable {
        public var harnessVersion: String
        public var appBundle: String
        public var pid: Int32

        public init(harnessVersion: String, appBundle: String, pid: Int32) {
            self.harnessVersion = harnessVersion
            self.appBundle = appBundle
            self.pid = pid
        }

        private enum CodingKeys: String, CodingKey {
            case harnessVersion = "harness_version"
            case appBundle = "app_bundle"
            case pid
        }
    }
}

// MARK: - read_state

extension PryWire {
    public struct ReadStateParams: Codable, Sendable {
        public var viewmodel: String
        public var path: String?

        public init(viewmodel: String, path: String? = nil) {
            self.viewmodel = viewmodel
            self.path = path
        }
    }

    /// Two mutually exclusive shapes depending on whether `path` was provided.
    public struct ReadStateResult: Codable, Sendable {
        /// Present when `path` was provided — the specific value at that key.
        public var value: AnyCodable?
        /// Present when `path` was omitted — the full snapshot keyed by registered path.
        public var keys: [String: AnyCodable]?

        public init(value: AnyCodable) {
            self.value = value
            self.keys = nil
        }

        public init(keys: [String: AnyCodable]) {
            self.value = nil
            self.keys = keys
        }
    }
}

// MARK: - inspect_tree

extension PryWire {
    public struct InspectTreeParams: Codable, Sendable {
        public var window: WindowPredicate?
        public init(window: WindowPredicate? = nil) { self.window = window }
    }

    public struct InspectTreeResult: Codable, Sendable {
        public var yaml: String
        public init(yaml: String) { self.yaml = yaml }
    }

    public struct WindowPredicate: Codable, Sendable {
        public var title: String?
        public var titleMatches: String?

        public init(title: String? = nil, titleMatches: String? = nil) {
            self.title = title
            self.titleMatches = titleMatches
        }

        private enum CodingKeys: String, CodingKey {
            case title
            case titleMatches = "title_matches"
        }
    }
}

// MARK: - read_logs

extension PryWire {
    public struct ReadLogsParams: Codable, Sendable {
        public var since: String?        // ISO8601
        public var subsystem: String?

        public init(since: String? = nil, subsystem: String? = nil) {
            self.since = since
            self.subsystem = subsystem
        }
    }

    public struct LogLine: Codable, Sendable {
        public var ts: String            // ISO8601
        public var level: String
        public var msg: String
        public var subsystem: String?
        public var category: String?

        public init(ts: String, level: String, msg: String, subsystem: String? = nil, category: String? = nil) {
            self.ts = ts; self.level = level; self.msg = msg
            self.subsystem = subsystem; self.category = category
        }
    }

    public struct ReadLogsResult: Codable, Sendable {
        public var lines: [LogLine]
        public var cursor: String        // ISO8601 for next call

        public init(lines: [LogLine], cursor: String) {
            self.lines = lines; self.cursor = cursor
        }
    }
}

// MARK: - snapshot

extension PryWire {
    public struct SnapshotParams: Codable, Sendable {
        public var window: WindowPredicate?
        public init(window: WindowPredicate? = nil) { self.window = window }
    }

    public struct SnapshotResult: Codable, Sendable {
        public var pngBase64: String

        public init(pngBase64: String) { self.pngBase64 = pngBase64 }

        private enum CodingKeys: String, CodingKey { case pngBase64 = "png_base64" }
    }
}

// MARK: - clock

extension PryWire {
    public struct ClockGetParams: Codable, Sendable { public init() {} }
    public struct ClockGetResult: Codable, Sendable {
        public var iso8601: String
        public var paused: Bool
        public init(iso8601: String, paused: Bool) {
            self.iso8601 = iso8601; self.paused = paused
        }
    }

    public struct ClockSetParams: Codable, Sendable {
        public var iso8601: String
        public var paused: Bool?
        public init(iso8601: String, paused: Bool? = nil) {
            self.iso8601 = iso8601; self.paused = paused
        }
    }
    public struct ClockSetResult: Codable, Sendable {
        public var iso8601: String
        public var firedCallbacks: Int
        public init(iso8601: String, firedCallbacks: Int) {
            self.iso8601 = iso8601; self.firedCallbacks = firedCallbacks
        }
        private enum CodingKeys: String, CodingKey {
            case iso8601
            case firedCallbacks = "fired_callbacks"
        }
    }

    public struct ClockAdvanceParams: Codable, Sendable {
        public var seconds: Double
        public init(seconds: Double) { self.seconds = seconds }
    }
}

// MARK: - animations

extension PryWire {
    public struct SetAnimationsParams: Codable, Sendable {
        public var enabled: Bool
        public init(enabled: Bool) { self.enabled = enabled }
    }
    public struct SetAnimationsResult: Codable, Sendable {
        public var enabled: Bool
        public init(enabled: Bool) { self.enabled = enabled }
    }
}

// MARK: - subscribe

extension PryWire {
    public struct SubscribeParams: Codable, Sendable {
        public var kinds: [String]            // NotificationKind raw values; empty = all
        public init(kinds: [String]) { self.kinds = kinds }
    }
    public struct SubscribeResult: Codable, Sendable {
        public var subscriptionID: String
        public init(subscriptionID: String) { self.subscriptionID = subscriptionID }
        private enum CodingKeys: String, CodingKey { case subscriptionID = "subscription_id" }
    }
    public struct UnsubscribeParams: Codable, Sendable {
        public var subscriptionID: String
        public init(subscriptionID: String) { self.subscriptionID = subscriptionID }
        private enum CodingKeys: String, CodingKey { case subscriptionID = "subscription_id" }
    }
    public struct UnsubscribeResult: Codable, Sendable { public init() {} }
}

// MARK: - pasteboard

extension PryWire {
    public struct ReadPasteboardParams: Codable, Sendable {
        public var type: String?              // "string", "url", "any"
        public init(type: String? = nil) { self.type = type }
    }
    public struct ReadPasteboardResult: Codable, Sendable {
        public var string: String?
        public var types: [String]
        public init(string: String?, types: [String]) {
            self.string = string; self.types = types
        }
    }
    public struct WritePasteboardParams: Codable, Sendable {
        public var string: String
        public init(string: String) { self.string = string }
    }
    public struct WritePasteboardResult: Codable, Sendable { public init() {} }
}

// MARK: - goodbye

extension PryWire {
    public struct GoodbyeParams: Codable, Sendable {
        public init() {}
    }

    public struct GoodbyeResult: Codable, Sendable {
        public init() {}
    }
}

// MARK: - AnyCodable

extension PryWire {

/// Type-erased JSON-friendly value. Covers the scalar types we carry across the wire
/// (Int, Double, Bool, String, null) plus nested arrays and objects. Anything else
/// round-trips as String via `String(describing:)`.
public struct AnyCodable: Codable, Sendable {
    public let value: any Sendable

    public init(_ value: any Sendable) {
        self.value = value
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = NullSentinel()
        } else if let b = try? container.decode(Bool.self) {
            self.value = b
        } else if let i = try? container.decode(Int.self) {
            self.value = i
        } else if let d = try? container.decode(Double.self) {
            self.value = d
        } else if let s = try? container.decode(String.self) {
            self.value = s
        } else if let arr = try? container.decode([AnyCodable].self) {
            self.value = arr.map { $0.value }
        } else if let obj = try? container.decode([String: AnyCodable].self) {
            self.value = obj.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case is NullSentinel: try container.encodeNil()
        case let b as Bool: try container.encode(b)
        case let i as Int: try container.encode(i)
        case let d as Double: try container.encode(d)
        case let s as String: try container.encode(s)
        case let arr as [any Sendable]:
            try container.encode(arr.map { AnyCodable($0) })
        case let obj as [String: any Sendable]:
            try container.encode(obj.mapValues { AnyCodable($0) })
        default:
            try container.encode(String(describing: value))
        }
    }

    public struct NullSentinel: Sendable {}
}

} // extension PryWire
