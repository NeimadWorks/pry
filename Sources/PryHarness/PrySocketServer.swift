import Foundation
import Darwin
import PryWire

/// Unix-domain stream socket server speaking the PryWire JSON-RPC protocol.
///
/// Single-threaded per client: each accepted connection is handled serially on
/// a dedicated dispatch queue. That's plenty for the volumes Pry expects
/// (one or two clients, tens of requests per test run).
final class PrySocketServer: @unchecked Sendable {
    private let socketPath: String
    private let appBundle: String

    private var listenFD: Int32 = -1
    private let acceptQueue = DispatchQueue(label: "fr.neimad.pry.harness.accept", qos: .utility)
    private var running = false
    private let lock = NSLock()

    init(socketPath: String, appBundle: String) {
        self.socketPath = socketPath
        self.appBundle = appBundle
    }

    func start() throws {
        lock.lock(); defer { lock.unlock() }
        guard !running else { return }

        // Remove stale socket from a prior crash.
        unlink(socketPath)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Error.socketCreate(errno: errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        // sun_path is fixed-size; ensure path fits.
        let pathBytes = Array(socketPath.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard pathBytes.count <= maxLen else {
            close(fd)
            throw Error.socketPathTooLong(socketPath)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, byte) in pathBytes.enumerated() {
                ptr[i] = byte
            }
            ptr[pathBytes.count] = 0
        }

        let bindErr = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                bind(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindErr == 0 else {
            let e = errno
            close(fd)
            throw Error.bind(errno: e, path: socketPath)
        }

        guard listen(fd, 4) == 0 else {
            let e = errno
            close(fd)
            throw Error.listen(errno: e)
        }

        self.listenFD = fd
        self.running = true
        acceptQueue.async { [weak self] in self?.acceptLoop() }
    }

    func stop() {
        lock.lock()
        running = false
        let fd = listenFD
        listenFD = -1
        lock.unlock()

        if fd >= 0 { close(fd) }
        unlink(socketPath)
    }

    // MARK: - Accept loop

    private func acceptLoop() {
        while true {
            lock.lock()
            let fd = listenFD
            let isRunning = running
            lock.unlock()
            guard isRunning, fd >= 0 else { return }

            let client = accept(fd, nil, nil)
            if client < 0 {
                if errno == EINTR { continue }
                return
            }

            let clientQueue = DispatchQueue(label: "fr.neimad.pry.harness.client.\(client)", qos: .utility)
            clientQueue.async { [weak self] in self?.handle(clientFD: client) }
        }
    }

    // MARK: - Per-client request/response loop

    private func handle(clientFD: Int32) {
        defer { close(clientFD) }

        while let frame = FrameIO.readFrame(fd: clientFD) {
            let response = dispatch(frame: frame)
            if !FrameIO.writeFrame(fd: clientFD, data: response) { return }
        }
    }

    private func dispatch(frame: Data) -> Data {
        let decoder = JSONDecoder()
        let encoder = JSONEncoder()

        // Parse envelope generically
        guard let raw = try? decoder.decode(PryWire.RawRequest.self, from: frame) else {
            let resp = PryWire.RawResponse(
                jsonrpc: "2.0", id: 0, result: nil,
                error: .init(code: PryWire.RPCError.parseError, message: "invalid JSON-RPC request")
            )
            return (try? encoder.encode(resp)) ?? Data()
        }

        guard let method = PryWire.Method(rawValue: raw.method) else {
            return encodeError(id: raw.id, code: PryWire.RPCError.methodNotFound, message: "unknown method: \(raw.method)", encoder: encoder)
        }

        switch method {
        case .hello:
            return handleHello(id: raw.id, params: raw.params, encoder: encoder, decoder: decoder)
        case .readState:
            return handleReadState(id: raw.id, params: raw.params, encoder: encoder, decoder: decoder)
        case .readLogs:
            return handleReadLogs(id: raw.id, params: raw.params, encoder: encoder, decoder: decoder)
        case .inspectTree, .snapshot:
            // These are handled out-of-process in pry-mcp — the harness doesn't
            // need to own AX walks or window captures. See ADR-002.
            return encodeError(id: raw.id, code: PryWire.RPCError.methodNotFound,
                               message: "method '\(raw.method)' lives out-of-process in pry-mcp",
                               encoder: encoder)
        case .goodbye:
            let resp = PryWire.Response(id: raw.id, result: PryWire.GoodbyeResult())
            return (try? encoder.encode(resp)) ?? Data()
        }
    }

    // MARK: - read_logs

    private func handleReadLogs(id: Int, params: PryWire.AnyCodable, encoder: JSONEncoder, decoder: JSONDecoder) -> Data {
        let p: PryWire.ReadLogsParams
        if let reencoded = try? encoder.encode(params),
           let parsed = try? decoder.decode(PryWire.ReadLogsParams.self, from: reencoded) {
            p = parsed
        } else {
            p = PryWire.ReadLogsParams()
        }

        let since: Date? = {
            guard let s = p.since else { return nil }
            return ISO8601DateFormatter().date(from: s)
        }()

        let lines = PryLogTap.readLines(since: since, subsystem: p.subsystem)
        let isoOut = ISO8601DateFormatter()
        let cursor = lines.last?.date ?? Date()
        let wireLines = lines.map {
            PryWire.LogLine(
                ts: isoOut.string(from: $0.date),
                level: $0.level,
                msg: $0.message,
                subsystem: $0.subsystem,
                category: $0.category
            )
        }
        let result = PryWire.ReadLogsResult(lines: wireLines, cursor: isoOut.string(from: cursor))
        let resp = PryWire.Response(id: id, result: result)
        return (try? encoder.encode(resp)) ?? Data()
    }

    // MARK: - Handlers

    private func handleHello(id: Int, params: PryWire.AnyCodable, encoder: JSONEncoder, decoder: JSONDecoder) -> Data {
        let result = PryWire.HelloResult(
            harnessVersion: PryHarness.version,
            appBundle: appBundle,
            pid: getpid()
        )
        let resp = PryWire.Response(id: id, result: result)
        return (try? encoder.encode(resp)) ?? Data()
    }

    private func handleReadState(id: Int, params: PryWire.AnyCodable, encoder: JSONEncoder, decoder: JSONDecoder) -> Data {
        // Re-encode and decode to pull typed params.
        guard let reencoded = try? encoder.encode(params),
              let p = try? decoder.decode(PryWire.ReadStateParams.self, from: reencoded) else {
            return encodeError(id: id, code: PryWire.RPCError.invalidParams,
                               message: "read_state requires { viewmodel: string, path?: string }",
                               encoder: encoder)
        }

        // Hop to main actor to read snapshot (PryRegistry is @MainActor).
        let snapshot = DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                PryRegistry.shared.snapshot(of: p.viewmodel)
            }
        }

        guard let snapshot else {
            let registered = DispatchQueue.main.sync {
                MainActor.assumeIsolated { PryRegistry.shared.registeredNames() }
            }
            return encodeError(
                id: id,
                code: PryWire.RPCError.viewmodelNotRegistered,
                message: "viewmodel '\(p.viewmodel)' is not registered",
                extra: ["registered": PryWire.AnyCodable(registered)],
                encoder: encoder
            )
        }

        if let path = p.path {
            guard let value = snapshot[path] else {
                return encodeError(
                    id: id,
                    code: PryWire.RPCError.pathNotFound,
                    message: "path '\(path)' not present in snapshot of '\(p.viewmodel)'",
                    extra: ["available_paths": PryWire.AnyCodable(Array(snapshot.keys).sorted())],
                    encoder: encoder
                )
            }
            let resp = PryWire.Response(id: id, result: PryWire.ReadStateResult(value: PryWire.AnyCodable(value)))
            return (try? encoder.encode(resp)) ?? Data()
        } else {
            let coerced = snapshot.mapValues { PryWire.AnyCodable($0) }
            let resp = PryWire.Response(id: id, result: PryWire.ReadStateResult(keys: coerced))
            return (try? encoder.encode(resp)) ?? Data()
        }
    }

    // MARK: - Error encoding

    private func encodeError(id: Int, code: Int, message: String, extra: [String: PryWire.AnyCodable]? = nil, encoder: JSONEncoder) -> Data {
        let err = PryWire.RPCError(code: code, message: message, data: extra)
        let resp = PryWire.RawResponse(jsonrpc: "2.0", id: id, result: nil, error: err)
        return (try? encoder.encode(resp)) ?? Data()
    }

    // MARK: - Errors

    enum Error: Swift.Error, CustomStringConvertible {
        case socketCreate(errno: Int32)
        case socketPathTooLong(String)
        case bind(errno: Int32, path: String)
        case listen(errno: Int32)

        var description: String {
            switch self {
            case .socketCreate(let e): return "socket(AF_UNIX) failed: errno=\(e)"
            case .socketPathTooLong(let p): return "socket path too long (>\(MemoryLayout<sockaddr_un>.size)): \(p)"
            case .bind(let e, let p): return "bind(\(p)) failed: errno=\(e)"
            case .listen(let e): return "listen() failed: errno=\(e)"
            }
        }
    }
}

// MARK: - Framing

enum FrameIO {
    /// Reads one length-prefixed frame. 4-byte big-endian length, then payload.
    /// Returns nil on EOF or error.
    static func readFrame(fd: Int32) -> Data? {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        guard readExactly(fd: fd, into: &lenBuf, count: 4) else { return nil }
        let len = UInt32(lenBuf[0]) << 24 | UInt32(lenBuf[1]) << 16 | UInt32(lenBuf[2]) << 8 | UInt32(lenBuf[3])

        if len == 0 { return Data() }
        if len > 16 * 1024 * 1024 { return nil } // 16 MB cap — anything larger is wrong

        var payload = [UInt8](repeating: 0, count: Int(len))
        guard readExactly(fd: fd, into: &payload, count: Int(len)) else { return nil }
        return Data(payload)
    }

    /// Writes one length-prefixed frame. Returns false on error.
    static func writeFrame(fd: Int32, data: Data) -> Bool {
        let len = UInt32(data.count)
        var header: [UInt8] = [
            UInt8((len >> 24) & 0xff),
            UInt8((len >> 16) & 0xff),
            UInt8((len >> 8) & 0xff),
            UInt8(len & 0xff),
        ]
        if !writeExactly(fd: fd, bytes: &header, count: 4) { return false }
        guard data.count > 0 else { return true }
        return data.withUnsafeBytes { raw -> Bool in
            guard let base = raw.baseAddress else { return false }
            return writeExactlyPtr(fd: fd, ptr: base, count: data.count)
        }
    }

    private static func readExactly(fd: Int32, into buf: UnsafeMutablePointer<UInt8>, count: Int) -> Bool {
        var off = 0
        while off < count {
            let n = recv(fd, buf.advanced(by: off), count - off, 0)
            if n == 0 { return false }
            if n < 0 { if errno == EINTR { continue }; return false }
            off += n
        }
        return true
    }

    private static func readExactly(fd: Int32, into buf: inout [UInt8], count: Int) -> Bool {
        buf.withUnsafeMutableBufferPointer { bp in
            guard let base = bp.baseAddress else { return false }
            return readExactly(fd: fd, into: base, count: count)
        }
    }

    private static func writeExactly(fd: Int32, bytes: inout [UInt8], count: Int) -> Bool {
        bytes.withUnsafeBufferPointer { bp in
            guard let base = bp.baseAddress else { return false }
            return writeExactlyPtr(fd: fd, ptr: base, count: count)
        }
    }

    private static func writeExactlyPtr(fd: Int32, ptr: UnsafeRawPointer, count: Int) -> Bool {
        var off = 0
        while off < count {
            let n = send(fd, ptr.advanced(by: off), count - off, 0)
            if n < 0 { if errno == EINTR { continue }; return false }
            off += n
        }
        return true
    }
}
