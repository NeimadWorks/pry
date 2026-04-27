import Foundation

/// Filesystem fixture management for `with_fs:` frontmatter blocks.
///
/// Creates a per-spec sandbox directory before launch and removes it after
/// teardown. Resolves `${spec_id}` placeholders in `basePath`. Supports three
/// entry kinds: `file`, `dir`, `copy` (from a source path).
public enum FilesystemFixtures {

    public static func install(_ fixture: FilesystemFixture, specID: String) throws -> URL {
        let resolved = fixture.basePath
            .replacingOccurrences(of: "${spec_id}", with: specID)
            .replacingOccurrences(of: "~", with: NSHomeDirectory())
        let url = URL(fileURLWithPath: resolved).standardizedFileURL

        // Wipe any prior sandbox.
        try? FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        for entry in fixture.entries {
            switch entry {
            case .directory(let path):
                let target = url.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
            case .file(let path, let content):
                let target = url.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: target, atomically: true, encoding: .utf8)
            case .copy(let path, let source):
                let src = URL(fileURLWithPath: source)
                let target = url.appendingPathComponent(path)
                try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                try? FileManager.default.removeItem(at: target)
                try FileManager.default.copyItem(at: src, to: target)
            }
        }

        return url
    }

    public static func cleanup(_ baseURL: URL) {
        try? FileManager.default.removeItem(at: baseURL)
    }
}

/// `with_defaults:` — write per-app NSUserDefaults via `defaults` shell tool,
/// snapshot the previous values for restore.
public enum DefaultsFixtures {

    public struct Snapshot: Sendable {
        public let bundleID: String
        public let touched: [String: String?]   // key → previous value (nil if unset)
    }

    public static func install(bundleID: String, values: [String: YAMLValue]) -> Snapshot {
        var touched: [String: String?] = [:]
        for (k, v) in values {
            touched[k] = readDefault(bundleID: bundleID, key: k)
            writeDefault(bundleID: bundleID, key: k, value: stringify(v))
        }
        return Snapshot(bundleID: bundleID, touched: touched)
    }

    public static func restore(_ snapshot: Snapshot) {
        for (k, prev) in snapshot.touched {
            if let prev {
                writeDefault(bundleID: snapshot.bundleID, key: k, value: prev)
            } else {
                deleteDefault(bundleID: snapshot.bundleID, key: k)
            }
        }
    }

    private static func stringify(_ v: YAMLValue) -> String {
        switch v {
        case .string(let s): return s
        case .identifier(let s): return s
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return b ? "1" : "0"
        case .null: return ""
        case .duration(let s): return String(s)
        case .array(let arr): return arr.compactMap(\.asString).joined(separator: ",")
        case .object: return ""
        }
    }

    @discardableResult
    private static func runDefaults(_ args: [String]) -> String {
        let p = Process()
        p.launchPath = "/usr/bin/defaults"
        p.arguments = args
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch { return "" }
    }

    private static func readDefault(bundleID: String, key: String) -> String? {
        let r = runDefaults(["read", bundleID, key]).trimmingCharacters(in: .whitespacesAndNewlines)
        return r.isEmpty ? nil : r
    }

    private static func writeDefault(bundleID: String, key: String, value: String) {
        runDefaults(["write", bundleID, key, value])
    }

    private static func deleteDefault(bundleID: String, key: String) {
        runDefaults(["delete", bundleID, key])
    }
}
