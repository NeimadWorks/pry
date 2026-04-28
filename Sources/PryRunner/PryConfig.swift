import Foundation

/// Project-level configuration for Pry, loaded from `.pry/config.yaml` at the
/// nearest ancestor of a spec file (walks up to 8 levels). Lets specs omit
/// `executable_path:` from their frontmatter — particularly useful for
/// SwiftPM-built apps whose path varies per machine.
///
/// Format:
///
///     apps:
///       fr.neimad.works.narrow:
///         executable_path: ./.build/arm64-apple-macosx/debug/Narrow
///       fr.neimad.proof:
///         executable_path: /Applications/Proof.app/Contents/MacOS/Proof
///
/// Paths can be relative to the config file's directory and may use `~` and
/// `${swift_bin}` (resolved via `swift build --show-bin-path`).
public struct PryConfig: Sendable {
    public struct AppConfig: Sendable {
        public var executablePath: String?
        /// When true, the runner runs `swift build` from the config file's
        /// directory before launching the target. Cuts the bundle.sh / .app
        /// repackage cycle; the executable_path can point straight at
        /// `.build/<arch>/debug/<Product>`.
        public var autoBuild: Bool

        public init(executablePath: String? = nil, autoBuild: Bool = false) {
            self.executablePath = executablePath
            self.autoBuild = autoBuild
        }
    }

    public var configFileURL: URL?
    public var apps: [String: AppConfig]

    public init(configFileURL: URL? = nil, apps: [String: AppConfig] = [:]) {
        self.configFileURL = configFileURL
        self.apps = apps
    }

    /// Lookup whether `swift build` should run before launching this app.
    public func autoBuild(for bundleID: String) -> Bool {
        apps[bundleID]?.autoBuild ?? false
    }

    /// Run `swift build` from the config file's directory. Used by
    /// `auto_build: true`. Best-effort — if the build fails, the launch
    /// will fail with a clearer error message anyway.
    public func runSwiftBuild() throws {
        guard let dir = configFileURL?.deletingLastPathComponent() else { return }
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["swift", "build"]
        p.currentDirectoryURL = dir
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: data, encoding: .utf8) ?? "swift build failed"
            throw NSError(domain: "PryConfig", code: Int(p.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: msg])
        }
    }

    /// Lookup the executable path for a given bundle ID, applying env-var
    /// override and `${swift_bin}` interpolation.
    public func resolveExecutablePath(for bundleID: String) -> String? {
        // Highest precedence: env var. Bundle ID dots become underscores so
        // `PRY_EXEC_FR_NEIMAD_NARROW` overrides `fr.neimad.narrow`.
        let envKey = "PRY_EXEC_" + bundleID
            .uppercased()
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
        if let v = ProcessInfo.processInfo.environment[envKey], !v.isEmpty {
            return expand(v, baseDir: configFileURL?.deletingLastPathComponent())
        }
        guard let raw = apps[bundleID]?.executablePath else { return nil }
        return expand(raw, baseDir: configFileURL?.deletingLastPathComponent())
    }

    private func expand(_ raw: String, baseDir: URL?) -> String {
        var s = raw.replacingOccurrences(of: "~", with: NSHomeDirectory())
        if s.contains("${swift_bin}") {
            let swiftBin = (try? Self.resolveSwiftBin(baseDir: baseDir)) ?? ""
            s = s.replacingOccurrences(of: "${swift_bin}", with: swiftBin)
        }
        if s.hasPrefix("/") { return s }
        if let baseDir { return baseDir.appendingPathComponent(s).standardizedFileURL.path }
        return s
    }

    private static func resolveSwiftBin(baseDir: URL?) throws -> String {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["swift", "build", "--show-bin-path"]
        if let baseDir { p.currentDirectoryURL = baseDir }
        let out = Pipe()
        p.standardOutput = out
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    // MARK: - Loading

    /// Walk up from `start` looking for `.pry/config.yaml`. Returns `nil` when
    /// no config is found within 8 levels.
    public static func discover(from start: URL) -> PryConfig? {
        var dir = start
        if !((try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false) {
            dir = dir.deletingLastPathComponent()
        }
        for _ in 0..<8 {
            let candidate = dir.appendingPathComponent(".pry/config.yaml")
            if FileManager.default.fileExists(atPath: candidate.path) {
                if let cfg = try? load(from: candidate) { return cfg }
            }
            let parent = dir.deletingLastPathComponent()
            if parent.path == dir.path { break }
            dir = parent
        }
        return nil
    }

    public static func load(from url: URL) throws -> PryConfig {
        let raw = try String(contentsOf: url, encoding: .utf8)
        var apps: [String: AppConfig] = [:]

        // Tiny YAML parser tailored to our shape — we don't pull in a YAML lib.
        // Acceptable forms:
        //
        //     apps:
        //       BUNDLE_ID:
        //         executable_path: PATH
        //       OTHER_BUNDLE_ID:
        //         executable_path: PATH
        //
        // Comments via `#` and blank lines are ignored. Indentation is
        // 2 or 4 spaces; mixed is OK as long as it's consistent within a block.
        let lines = raw.components(separatedBy: "\n")
        var inApps = false
        var currentBundle: String?
        for raw in lines {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let indent = raw.prefix(while: { $0 == " " || $0 == "\t" }).count
            if indent == 0 {
                inApps = (trimmed.hasPrefix("apps:") || trimmed == "apps:")
                currentBundle = nil
                continue
            }
            guard inApps else { continue }
            // Bundle key — has its own indent level, ends with ':'
            if trimmed.hasSuffix(":") && !trimmed.contains(": ") {
                currentBundle = String(trimmed.dropLast()).trimmingCharacters(in: .whitespaces)
                if let id = currentBundle, apps[id] == nil { apps[id] = AppConfig() }
                continue
            }
            // Field under bundle.
            guard let bundle = currentBundle else { continue }
            if let colon = trimmed.firstIndex(of: ":") {
                let key = String(trimmed[..<colon]).trimmingCharacters(in: .whitespaces)
                let val = String(trimmed[trimmed.index(after: colon)...])
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if key == "executable_path" {
                    apps[bundle, default: AppConfig()].executablePath = val
                }
                if key == "auto_build" {
                    let lc = val.lowercased()
                    apps[bundle, default: AppConfig()].autoBuild =
                        (lc == "true" || lc == "yes" || lc == "on" || lc == "1")
                }
            }
        }
        return PryConfig(configFileURL: url, apps: apps)
    }
}
