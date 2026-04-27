import Foundation
import Darwin
import PryWire

/// Unix-socket client for PryHarness. Serializes requests via actor isolation
/// so JSON-RPC IDs match 1:1 with responses.
public actor HarnessClient {
    public enum ClientError: Error, CustomStringConvertible {
        case socketCreate(errno: Int32)
        case socketPathTooLong(String)
        case connect(errno: Int32, path: String)
        case writeFailed
        case readFailed
        case decodeFailed(String)
        case rpcError(PryWire.RPCError)

        public var description: String {
            switch self {
            case .socketCreate(let e): return "socket(AF_UNIX) failed: errno=\(e)"
            case .socketPathTooLong(let p): return "socket path too long: \(p)"
            case .connect(let e, let p): return "connect(\(p)) failed: errno=\(e) (harness not listening?)"
            case .writeFailed: return "socket write failed"
            case .readFailed: return "socket read failed / disconnected"
            case .decodeFailed(let s): return "decode failed: \(s)"
            case .rpcError(let err):
                var msg = "rpc error \(err.code): \(err.message)"
                if let data = err.data { msg += " data=\(data)" }
                return msg
            }
        }
    }

    private var fd: Int32 = -1
    private var nextID: Int = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(connectingTo path: String) throws {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.socketCreate(errno: errno) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path) - 1
        guard pathBytes.count <= maxLen else {
            close(fd); throw ClientError.socketPathTooLong(path)
        }
        withUnsafeMutableBytes(of: &addr.sun_path) { ptr in
            for (i, byte) in pathBytes.enumerated() { ptr[i] = byte }
            ptr[pathBytes.count] = 0
        }

        let rc = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { saPtr in
                Darwin.connect(fd, saPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard rc == 0 else {
            let e = errno; close(fd)
            throw ClientError.connect(errno: e, path: path)
        }

        self.fd = fd
    }

    deinit {
        if fd >= 0 { close(fd) }
    }

    // MARK: - Method API

    public func hello(client: String, version: String) throws -> PryWire.HelloResult {
        try call(method: .hello, params: PryWire.HelloParams(client: client, version: version))
    }

    public func readState(viewmodel: String, path: String?) throws -> PryWire.ReadStateResult {
        try call(method: .readState, params: PryWire.ReadStateParams(viewmodel: viewmodel, path: path))
    }

    public func readLogs(since: String?, subsystem: String?) throws -> PryWire.ReadLogsResult {
        try call(method: .readLogs, params: PryWire.ReadLogsParams(since: since, subsystem: subsystem))
    }

    public func goodbye() throws {
        let _: PryWire.GoodbyeResult = try call(method: .goodbye, params: PryWire.GoodbyeParams())
    }

    // MARK: - Generic call

    private func call<P: Codable & Sendable, R: Codable & Sendable>(method: PryWire.Method, params: P) throws -> R {
        nextID += 1
        let req = PryWire.Request(id: nextID, method: method.rawValue, params: params)
        let data = try encoder.encode(req)
        guard FrameIO.writeFrame(fd: fd, data: data) else { throw ClientError.writeFailed }

        guard let respData = FrameIO.readFrame(fd: fd) else { throw ClientError.readFailed }

        // Peek at error first using RawResponse.
        if let raw = try? decoder.decode(PryWire.RawResponse.self, from: respData), let err = raw.error {
            throw ClientError.rpcError(err)
        }

        do {
            let resp = try decoder.decode(PryWire.Response<R>.self, from: respData)
            if let err = resp.error { throw ClientError.rpcError(err) }
            guard let result = resp.result else {
                throw ClientError.decodeFailed("response has neither result nor error")
            }
            return result
        } catch let e as ClientError {
            throw e
        } catch {
            throw ClientError.decodeFailed("\(error)")
        }
    }
}

// MARK: - Framing (mirror of PryHarness's FrameIO — kept duplicated to keep
// PryWire logic-free per ADR-002)

enum FrameIO {
    static func readFrame(fd: Int32) -> Data? {
        var lenBuf = [UInt8](repeating: 0, count: 4)
        guard readExactly(fd: fd, into: &lenBuf, count: 4) else { return nil }
        let len = UInt32(lenBuf[0]) << 24 | UInt32(lenBuf[1]) << 16 | UInt32(lenBuf[2]) << 8 | UInt32(lenBuf[3])
        if len == 0 { return Data() }
        if len > 16 * 1024 * 1024 { return nil }
        var payload = [UInt8](repeating: 0, count: Int(len))
        guard readExactly(fd: fd, into: &payload, count: Int(len)) else { return nil }
        return Data(payload)
    }

    static func writeFrame(fd: Int32, data: Data) -> Bool {
        let len = UInt32(data.count)
        var header: [UInt8] = [
            UInt8((len >> 24) & 0xff),
            UInt8((len >> 16) & 0xff),
            UInt8((len >> 8) & 0xff),
            UInt8(len & 0xff),
        ]
        if !writeExactly(fd: fd, bytes: &header, count: 4) { return false }
        guard !data.isEmpty else { return true }
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
