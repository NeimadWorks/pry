import Foundation

public enum SpecParseError: Error, CustomStringConvertible {
    case missingFrontmatter
    case frontmatterMalformed(String)
    case missingRequiredField(String)
    case unknownCommand(String, line: Int)
    case invalidArgument(String, line: Int)
    case unterminatedBlock(line: Int)

    public var description: String {
        switch self {
        case .missingFrontmatter: return "spec must start with YAML frontmatter enclosed by '---'"
        case .frontmatterMalformed(let s): return "frontmatter malformed: \(s)"
        case .missingRequiredField(let f): return "frontmatter missing required field: \(f)"
        case .unknownCommand(let c, let l): return "line \(l): unknown command '\(c)'"
        case .invalidArgument(let m, let l): return "line \(l): \(m)"
        case .unterminatedBlock(let l): return "line \(l): pry block not closed with '```'"
        }
    }
}

public enum SpecParser {

    public static func parse(source: String, sourcePath: String? = nil) throws -> Spec {
        // 1. Frontmatter
        let (frontmatterYaml, body) = try splitFrontmatter(source)
        let fm = try parseFrontmatter(frontmatterYaml)

        // 2. Resolve include: lines (before block extraction).
        var resolvedBody = body
        if let path = sourcePath {
            resolvedBody = try resolveIncludes(
                body: body,
                baseDir: URL(fileURLWithPath: path).deletingLastPathComponent()
            )
        }

        // 3. Apply variable interpolation: ${name} → value.
        let interpolated = interpolate(resolvedBody, vars: fm.variables)

        // 4. Extract typed blocks (main, setup, teardown, flow:NAME, handler:NAME on TRIGGER).
        let blocks = try extractTaggedBlocks(body: interpolated)

        var setup: [Step] = []
        var teardown: [Step] = []
        var main: [Step] = []
        var flows: [String: SpecFlow] = [:]
        var handlers: [SpecHandler] = []

        for b in blocks {
            let parsed = try parseBlock(b.text, startLine: b.startLine)
            switch b.kind {
            case .main: main.append(contentsOf: parsed)
            case .setup: setup.append(contentsOf: parsed)
            case .teardown: teardown.append(contentsOf: parsed)
            case .flow(let name, let params):
                flows[name] = SpecFlow(name: name, parameters: params, body: parsed)
            case .handler(let name, let trigger, let mode):
                handlers.append(SpecHandler(name: name, trigger: trigger, mode: mode, body: parsed))
            }
        }

        return Spec(
            id: fm.id,
            app: fm.app,
            description: fm.description,
            tags: fm.tags ?? [],
            timeout: fm.timeout ?? .defaultSpec,
            executablePath: fm.executablePath,
            sourcePath: sourcePath,
            animationsEnabled: fm.animationsEnabled,
            variables: fm.variables,
            setupSteps: setup,
            teardownSteps: teardown,
            handlers: handlers,
            flows: flows,
            withFS: fm.withFS,
            withDefaults: fm.withDefaults,
            screenshotsPolicy: fm.screenshotsPolicy,
            steps: main,
            sourceText: source
        )
    }

    // MARK: - Includes

    private static func resolveIncludes(body: String, baseDir: URL, depth: Int = 0) throws -> String {
        guard depth < 8 else {
            throw SpecParseError.frontmatterMalformed("include depth limit (8) exceeded — possible cycle")
        }
        var out: [String] = []
        for line in body.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("include:") {
                let rawPath = String(trimmed.dropFirst("include:".count))
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                let url = baseDir.appendingPathComponent(rawPath).standardizedFileURL
                guard let included = try? String(contentsOf: url, encoding: .utf8) else {
                    throw SpecParseError.frontmatterMalformed("cannot read include: \(url.path)")
                }
                let stripped = stripFrontmatterIfPresent(included)
                let nested = try resolveIncludes(body: stripped,
                                                 baseDir: url.deletingLastPathComponent(),
                                                 depth: depth + 1)
                out.append(nested)
            } else {
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }

    private static func stripFrontmatterIfPresent(_ text: String) -> String {
        guard text.hasPrefix("---") else { return text }
        let lines = text.components(separatedBy: "\n")
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                return lines[(i + 1)...].joined(separator: "\n")
            }
            i += 1
        }
        return text
    }

    // MARK: - Variables

    private static func interpolate(_ text: String, vars: [String: YAMLValue]) -> String {
        guard !vars.isEmpty else { return text }
        var out = text
        for (name, value) in vars {
            let needle = "${\(name)}"
            let replacement = renderYAMLValueForInterpolation(value)
            out = out.replacingOccurrences(of: needle, with: replacement)
        }
        return out
    }

    private static func renderYAMLValueForInterpolation(_ v: YAMLValue) -> String {
        switch v {
        case .string(let s): return "\"\(s)\""
        case .identifier(let s): return s
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .duration(let s): return "\(s)s"
        case .array(let arr): return "[\(arr.map(renderYAMLValueForInterpolation).joined(separator: ", "))]"
        case .object(let kvs):
            return "{\(kvs.map { "\($0.0): \(renderYAMLValueForInterpolation($0.1))" }.joined(separator: ", "))}"
        }
    }

    // MARK: - Tagged blocks

    private enum BlockKind {
        case main
        case setup
        case teardown
        case flow(name: String, params: [String])
        case handler(name: String, trigger: SpecHandler.Trigger, mode: SpecHandler.Mode)
    }
    private struct TaggedBlock { let kind: BlockKind; let text: String; let startLine: Int }

    private static func extractTaggedBlocks(body: String) throws -> [TaggedBlock] {
        var blocks: [TaggedBlock] = []
        let lines = body.components(separatedBy: "\n")
        var i = 0
        var inBlock = false
        var blockStart = 0
        var pendingKind: BlockKind = .main
        var buffer: [String] = []
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if trimmed.hasPrefix("```pry") {
                    inBlock = true
                    blockStart = i + 1
                    buffer.removeAll()
                    let suffix = String(trimmed.dropFirst("```pry".count)).trimmingCharacters(in: .whitespaces)
                    pendingKind = try parseBlockHeader(suffix, fenceLine: i + 1)
                }
            } else {
                if trimmed == "```" {
                    blocks.append(TaggedBlock(kind: pendingKind, text: buffer.joined(separator: "\n"), startLine: blockStart))
                    inBlock = false
                } else {
                    buffer.append(lines[i])
                }
            }
            i += 1
        }
        if inBlock { throw SpecParseError.unterminatedBlock(line: blockStart) }
        return blocks
    }

    private static func parseBlockHeader(_ suffix: String, fenceLine: Int) throws -> BlockKind {
        // Forms:
        //   "" (or whitespace) → main
        //   "setup" → setup
        //   "teardown" → teardown
        //   "flow NAME" or "flow NAME(p1, p2)" → flow
        //   "handler NAME on sheet:'Replace.*'" or "handler NAME on state:VM.path" or "handler NAME on window:Title.*" [once|always]
        let s = suffix.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return .main }
        if s == "setup" { return .setup }
        if s == "teardown" { return .teardown }

        if s.hasPrefix("flow ") {
            let rest = String(s.dropFirst("flow ".count))
            let (name, params) = splitNameAndParams(rest)
            return .flow(name: name, params: params)
        }

        if s.hasPrefix("handler ") {
            let rest = String(s.dropFirst("handler ".count))
            // Expect:  NAME on TRIGGER [once|always]
            let parts = rest.components(separatedBy: " on ")
            guard parts.count == 2 else {
                throw SpecParseError.invalidArgument("handler header: expected 'NAME on TRIGGER'", line: fenceLine)
            }
            let name = parts[0].trimmingCharacters(in: .whitespaces)
            var triggerSpec = parts[1].trimmingCharacters(in: .whitespaces)
            var mode: SpecHandler.Mode = .always
            if triggerSpec.hasSuffix(" once") {
                mode = .once
                triggerSpec = String(triggerSpec.dropLast(" once".count)).trimmingCharacters(in: .whitespaces)
            } else if triggerSpec.hasSuffix(" always") {
                mode = .always
                triggerSpec = String(triggerSpec.dropLast(" always".count)).trimmingCharacters(in: .whitespaces)
            }
            let trigger = try parseHandlerTrigger(triggerSpec, line: fenceLine)
            return .handler(name: name, trigger: trigger, mode: mode)
        }

        throw SpecParseError.invalidArgument("unknown block kind: '\(s)'", line: fenceLine)
    }

    private static func splitNameAndParams(_ s: String) -> (String, [String]) {
        if let lparen = s.firstIndex(of: "("), s.last == ")" {
            let name = String(s[..<lparen]).trimmingCharacters(in: .whitespaces)
            let inner = s[s.index(after: lparen)..<s.index(before: s.endIndex)]
            let params = inner.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            return (name, params)
        }
        return (s.trimmingCharacters(in: .whitespaces), [])
    }

    private static func parseHandlerTrigger(_ s: String, line: Int) throws -> SpecHandler.Trigger {
        // Forms:
        //   sheet:"Replace.*"
        //   sheet:any
        //   state:VMName.path  (or state:VMName.* for any path)
        //   window:"Compose.*"
        if s.hasPrefix("sheet:") {
            let arg = String(s.dropFirst("sheet:".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return .sheetAppeared(titleMatches: arg == "any" ? nil : arg)
        }
        if s.hasPrefix("window:") {
            let arg = String(s.dropFirst("window:".count)).trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
            return .windowAppeared(titleMatches: arg == "any" ? nil : arg)
        }
        if s.hasPrefix("state:") {
            let arg = String(s.dropFirst("state:".count)).trimmingCharacters(in: .whitespaces)
            // VM.path or VM.*
            if let dot = arg.firstIndex(of: ".") {
                let vm = String(arg[..<dot])
                let path = String(arg[arg.index(after: dot)...])
                return .stateChanged(viewmodel: vm, path: path == "*" ? nil : path)
            }
            return .stateChanged(viewmodel: arg, path: nil)
        }
        throw SpecParseError.invalidArgument("unknown handler trigger '\(s)'", line: line)
    }

    // MARK: - Frontmatter

    private struct Frontmatter {
        var id: String
        var app: String
        var description: String?
        var tags: [String]?
        var timeout: Duration?
        var executablePath: String?
        var animationsEnabled: Bool = true
        var variables: [String: YAMLValue] = [:]
        var withFS: FilesystemFixture? = nil
        var withDefaults: [String: YAMLValue] = [:]
        var screenshotsPolicy: ScreenshotsPolicy = .onFailure
    }

    private static func splitFrontmatter(_ source: String) throws -> (yaml: String, body: String) {
        let lines = source.components(separatedBy: "\n")
        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---" else {
            throw SpecParseError.missingFrontmatter
        }
        var yamlLines: [String] = []
        var i = 1
        while i < lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                let body = lines[(i + 1)...].joined(separator: "\n")
                return (yamlLines.joined(separator: "\n"), body)
            }
            yamlLines.append(lines[i])
            i += 1
        }
        throw SpecParseError.missingFrontmatter
    }

    private static func parseFrontmatter(_ yaml: String) throws -> Frontmatter {
        // Simple line-based frontmatter parser: supports
        //   key: value
        //   key: [a, b, c]
        //   key: "quoted"
        var map: [String: String] = [:]
        for raw in yaml.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            guard let colon = line.firstIndex(of: ":") else {
                throw SpecParseError.frontmatterMalformed("no colon in line: \(line)")
            }
            let key = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            map[key] = value
        }

        guard let id = map["id"] else { throw SpecParseError.missingRequiredField("id") }
        guard let app = map["app"] else { throw SpecParseError.missingRequiredField("app") }

        var fm = Frontmatter(id: unquote(id), app: unquote(app),
                             description: map["description"].map(unquote),
                             tags: nil, timeout: nil, executablePath: nil)

        if let tagsRaw = map["tags"] {
            // Expect [a, b, c]
            let trimmed = tagsRaw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                let inner = trimmed.dropFirst().dropLast()
                fm.tags = inner.split(separator: ",").map {
                    unquote($0.trimmingCharacters(in: .whitespaces))
                }
            }
        }

        if let t = map["timeout"] {
            let parsed = try? YAMLFlow.parse(t)
            if case .duration(let s) = parsed { fm.timeout = Duration(seconds: s) }
        }

        if let ep = map["executable_path"] {
            fm.executablePath = unquote(ep)
        }

        if let a = map["animations"] {
            let v = unquote(a).lowercased()
            fm.animationsEnabled = !(v == "off" || v == "false" || v == "no")
        }

        if let varsRaw = map["vars"] {
            // Inline form: vars: { name: "value", n: 3 }
            if let parsed = try? YAMLFlow.parse(varsRaw), case .object(let kvs) = parsed {
                for (k, v) in kvs { fm.variables[k] = v }
            }
        }

        if let raw = map["screenshots"] {
            let v = unquote(raw).lowercased()
            if let policy = ScreenshotsPolicy(rawValue: v) { fm.screenshotsPolicy = policy }
        }

        if let raw = map["with_defaults"] {
            if let parsed = try? YAMLFlow.parse(raw), case .object(let kvs) = parsed {
                for (k, v) in kvs { fm.withDefaults[k] = v }
            }
        }

        if let raw = map["with_fs"] {
            if let parsed = try? YAMLFlow.parse(raw), case .object(let kvs) = parsed {
                fm.withFS = parseFsFixture(kvs)
            }
        }

        return fm
    }

    private static func parseFsFixture(_ kvs: [(String, YAMLValue)]) -> FilesystemFixture? {
        var base: String?
        var entries: [FilesystemFixture.Entry] = []
        for (k, v) in kvs {
            if k == "base" { base = v.asString }
            if k == "layout", case .array(let arr) = v {
                for item in arr {
                    guard case .object(let i) = item else { continue }
                    if let path = i.first(where: { $0.0 == "file" })?.1.asString {
                        let content = i.first(where: { $0.0 == "content" })?.1.asString ?? ""
                        let source = i.first(where: { $0.0 == "source" })?.1.asString
                        if let source { entries.append(.copy(path: path, source: source)) }
                        else { entries.append(.file(path: path, content: content)) }
                    } else if let path = i.first(where: { $0.0 == "dir" })?.1.asString {
                        entries.append(.directory(path: path))
                    }
                }
            }
        }
        guard let base else { return nil }
        return FilesystemFixture(basePath: base, entries: entries)
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" else { return s }
        return String(s.dropFirst().dropLast())
    }

    // MARK: - Block extraction (legacy, untagged) — kept for tests / inline specs

    private static func extractPryBlocks(body: String) throws -> [(text: String, startLine: Int)] {
        var blocks: [(String, Int)] = []
        let lines = body.components(separatedBy: "\n")
        var i = 0
        var inBlock = false
        var blockStart = 0
        var buffer: [String] = []
        while i < lines.count {
            let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
            if !inBlock {
                if trimmed == "```pry" {
                    inBlock = true
                    blockStart = i + 1 // +1 because line numbers are 1-based, and we skip the fence line
                    buffer.removeAll()
                }
            } else {
                if trimmed == "```" {
                    blocks.append((buffer.joined(separator: "\n"), blockStart))
                    inBlock = false
                } else {
                    buffer.append(lines[i])
                }
            }
            i += 1
        }
        if inBlock { throw SpecParseError.unterminatedBlock(line: blockStart) }
        return blocks
    }

    // MARK: - Block parsing

    /// Parse one ```pry block into a list of Steps. Each "step" is one
    /// top-level line; indented continuation lines are gathered as the
    /// step's block (for commands like `assert_state:` without inline args).
    private static func parseBlock(_ text: String, startLine: Int) throws -> [Step] {
        let lines = text.components(separatedBy: "\n")

        // Pre-pass: pair top-level lines with any indented continuation lines.
        struct RawStep {
            let line: Int
            let head: String
            let block: [String]
        }

        var rawSteps: [RawStep] = []
        var i = 0
        while i < lines.count {
            let line = lines[i]
            let stripped = line.trimmingCharacters(in: .whitespaces)
            if stripped.isEmpty || stripped.hasPrefix("#") { i += 1; continue }

            // Top-level lines have no leading whitespace (or minimal).
            let leadingWS = line.prefix(while: \.isWhitespace).count
            if leadingWS > 0 {
                // Orphan indented line — attach to previous if present, else skip
                if var last = rawSteps.last {
                    rawSteps.removeLast()
                    var block = last.block
                    block.append(stripped)
                    last = RawStep(line: last.line, head: last.head, block: block)
                    rawSteps.append(last)
                }
                i += 1
                continue
            }

            // Gather any immediately-following indented lines as this step's block.
            var block: [String] = []
            var j = i + 1
            while j < lines.count {
                let n = lines[j]
                let nsStripped = n.trimmingCharacters(in: .whitespaces)
                if nsStripped.isEmpty { j += 1; continue }
                let nsLeading = n.prefix(while: \.isWhitespace).count
                if nsLeading == 0 { break }
                block.append(nsStripped)
                j += 1
            }

            rawSteps.append(RawStep(line: startLine + i, head: stripped, block: block))
            i = j
        }

        return try rawSteps.map { try parseStep($0.head, block: $0.block, lineNumber: $0.line) }
    }

    private static func parseStep(_ head: String, block: [String], lineNumber: Int) throws -> Step {
        // Split the head into command + rhs (may be empty for bare commands).
        let command: String
        let rhs: String
        if let colon = head.firstIndex(of: ":") {
            command = String(head[..<colon]).trimmingCharacters(in: .whitespaces)
            rhs = String(head[head.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        } else {
            command = head.trimmingCharacters(in: .whitespaces)
            rhs = ""
        }

        // For commands that take an indented block (no rhs or partial rhs),
        // merge the block into a pseudo-YAML-flow object.
        let mergedYAML: YAMLValue? = try {
            if !rhs.isEmpty && !block.isEmpty {
                // Timeout-style continuation: `wait_for: { ... }\n  timeout: 2s`
                // Parse rhs + append block entries as additional object fields.
                let head = try YAMLFlow.parse(rhs)
                guard case .object(var kvs) = head else {
                    // rhs isn't an object, just use rhs
                    return head
                }
                for line in block {
                    if let colon = line.firstIndex(of: ":") {
                        let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                        let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        let val = try YAMLFlow.parse(v)
                        kvs.append((k, val))
                    }
                }
                return .object(kvs)
            } else if !rhs.isEmpty {
                return try YAMLFlow.parse(rhs)
            } else if !block.isEmpty {
                // Build object from block lines
                var kvs: [(String, YAMLValue)] = []
                for line in block {
                    if let colon = line.firstIndex(of: ":") {
                        let k = String(line[..<colon]).trimmingCharacters(in: .whitespaces)
                        let v = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                        let val = try YAMLFlow.parse(v)
                        kvs.append((k, val))
                    }
                }
                return .object(kvs)
            } else {
                return nil
            }
        }()

        // Dispatch
        switch command {
        // Lifecycle
        case "launch":
            return .launch(args: [], env: [:])
        case "launch_with":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("launch_with needs { args: [...], env: {...} }", line: lineNumber)
            }
            var args: [String] = []
            var env: [String: String] = [:]
            for (k, v) in kvs {
                if k == "args", case .array(let arr) = v {
                    args = arr.compactMap(\.asString)
                } else if k == "env", case .object(let eo) = v {
                    for (ek, ev) in eo { if let s = ev.asString { env[ek] = s } }
                }
            }
            return .launch(args: args, env: env)
        case "terminate": return .terminate
        case "relaunch": return .relaunch

        // Waits
        case "wait_for":
            guard let yaml = mergedYAML else {
                throw SpecParseError.invalidArgument("wait_for needs a predicate", line: lineNumber)
            }
            var timeout = Duration.defaultWaitFor
            var predYAML: YAMLValue = yaml
            // If the object has a `timeout:` field, strip it and keep the rest as predicate.
            if case .object(let kvs) = yaml, kvs.contains(where: { $0.0 == "timeout" }) {
                var kept: [(String, YAMLValue)] = []
                for (k, v) in kvs {
                    if k == "timeout" {
                        if let s = v.asSeconds { timeout = Duration(seconds: s) }
                    } else {
                        kept.append((k, v))
                    }
                }
                predYAML = .object(kept)
            }
            let pred = try parsePredicate(predYAML, line: lineNumber)
            return .waitFor(predicate: pred, timeout: timeout)

        case "sleep":
            guard let yaml = mergedYAML, let s = yaml.asSeconds else {
                throw SpecParseError.invalidArgument("sleep needs a duration (e.g. 2s)", line: lineNumber)
            }
            return .sleep(Duration(seconds: s))

        // Control
        case "click":
            let (t, mods) = try parseTargetWithModifiers(mergedYAML, line: lineNumber)
            return .click(target: t, modifiers: mods)
        case "double_click":
            let (t, mods) = try parseTargetWithModifiers(mergedYAML, line: lineNumber)
            return .doubleClick(target: t, modifiers: mods)
        case "right_click":
            let (t, mods) = try parseTargetWithModifiers(mergedYAML, line: lineNumber)
            return .rightClick(target: t, modifiers: mods)
        case "hover":
            // Form A: hover: { id: "x" }  → no dwell
            // Form B: hover: { id: "x", dwell_ms: 800 }
            let dwell: Int? = {
                if case .object(let kvs)? = mergedYAML {
                    for (k, v) in kvs where k == "dwell_ms" { return v.asInt }
                }
                return nil
            }()
            return .hover(target: try parseTarget(mergedYAML, line: lineNumber), dwellMs: dwell)
        case "long_press":
            let dwell: Int = {
                if case .object(let kvs)? = mergedYAML {
                    for (k, v) in kvs where k == "dwell_ms" { return v.asInt ?? 800 }
                }
                return 800
            }()
            return .longPress(target: try parseTarget(mergedYAML, line: lineNumber), dwellMs: dwell)
        case "type":
            // Form A: type: "Hello"
            // Form B: type: { text: "Hello", delay_ms: 30 }
            if let s = mergedYAML?.asString {
                return .type(text: s, delayMs: nil)
            }
            if case .object(let kvs)? = mergedYAML {
                var text: String?; var delay: Int?
                for (k, v) in kvs {
                    if k == "text" { text = v.asString }
                    if k == "delay_ms" { delay = v.asInt }
                }
                guard let text else {
                    throw SpecParseError.invalidArgument("type needs text", line: lineNumber)
                }
                return .type(text: text, delayMs: delay)
            }
            throw SpecParseError.invalidArgument("type needs a string", line: lineNumber)
        case "key":
            // Form A: key: "cmd+s"
            // Form B: key: { combo: "down", repeat: 5 }
            if let s = mergedYAML?.asString {
                return .key(combo: s, repeatCount: 1)
            }
            if case .object(let kvs)? = mergedYAML {
                var combo: String?; var n: Int = 1
                for (k, v) in kvs {
                    if k == "combo" { combo = v.asString }
                    if k == "repeat" { n = v.asInt ?? 1 }
                }
                guard let combo else {
                    throw SpecParseError.invalidArgument("key needs combo", line: lineNumber)
                }
                return .key(combo: combo, repeatCount: n)
            }
            throw SpecParseError.invalidArgument("key needs a combo string", line: lineNumber)
        case "marquee":
            // Form: marquee: { from: { x: ..., y: ... }, to: { x: ..., y: ... }, modifiers: [shift] }
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("marquee needs { from, to }", line: lineNumber)
            }
            var fromP: PointSpec?; var toP: PointSpec?; var mods: [String] = []
            for (k, v) in kvs {
                if k == "from", case .object(let pts) = v {
                    fromP = parsePointSpec(pts)
                }
                if k == "to", case .object(let pts) = v {
                    toP = parsePointSpec(pts)
                }
                if k == "modifiers", case .array(let arr) = v {
                    mods = arr.compactMap(\.asString)
                }
            }
            guard let fromP, let toP else {
                throw SpecParseError.invalidArgument("marquee needs from{x,y} and to{x,y}", line: lineNumber)
            }
            return .marqueeDrag(from: fromP, to: toP, modifiers: mods)
        case "magnify":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("magnify needs { target, delta }", line: lineNumber)
            }
            var targetYAML: YAMLValue?; var delta: Int = 0
            for (k, v) in kvs {
                if k == "target" { targetYAML = v }
                if k == "delta" { delta = v.asInt ?? 0 }
            }
            return .magnify(target: try parseTarget(targetYAML, line: lineNumber), delta: delta)

        case "scroll":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("scroll needs { target, direction, amount }", line: lineNumber)
            }
            var targetYAML: YAMLValue?
            var direction: ScrollDirection = .down
            var amount: Int = 3
            for (k, v) in kvs {
                switch k {
                case "target": targetYAML = v
                case "direction":
                    guard let s = v.asString, let d = ScrollDirection(rawValue: s) else {
                        throw SpecParseError.invalidArgument("direction must be up|down|left|right", line: lineNumber)
                    }
                    direction = d
                case "amount":
                    if let n = v.asInt { amount = n }
                default: break
                }
            }
            let target = try Self.parseTarget(targetYAML, line: lineNumber)
            return .scroll(target: target, direction: direction, amount: amount)

        case "drag":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("drag needs { from, to }", line: lineNumber)
            }
            var fromYAML: YAMLValue?
            var toYAML: YAMLValue?
            var steps: Int = 12
            var modifiers: [String] = []
            for (k, v) in kvs {
                switch k {
                case "from": fromYAML = v
                case "to": toYAML = v
                case "steps": if let n = v.asInt { steps = n }
                case "modifiers":
                    if case .array(let arr) = v { modifiers = arr.compactMap(\.asString) }
                default: break
                }
            }
            let f = try Self.parseTarget(fromYAML, line: lineNumber)
            let t = try Self.parseTarget(toYAML, line: lineNumber)
            return .drag(from: f, to: t, steps: max(1, steps), modifiers: modifiers)

        // Assertions
        case "assert_tree":
            guard let yaml = mergedYAML else {
                throw SpecParseError.invalidArgument("assert_tree needs a predicate", line: lineNumber)
            }
            return .assertTree(predicate: try parsePredicate(yaml, line: lineNumber))
        case "assert_state":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("assert_state needs { viewmodel, path, equals|matches|any_of }", line: lineNumber)
            }
            return try buildAssertState(kvs, line: lineNumber)

        case "expect_change":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("expect_change needs { action, in, to }", line: lineNumber)
            }
            return try buildExpectChange(kvs, line: lineNumber)

        // Debug aids
        case "snapshot":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("snapshot needs a name", line: lineNumber)
            }
            return .snapshot(name: s)
        case "dump_tree":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("dump_tree needs a name", line: lineNumber)
            }
            return .dumpTree(name: s)
        case "dump_state":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("dump_state needs a name", line: lineNumber)
            }
            return .dumpState(name: s)

        // Wave 1
        case "clock.advance", "clock_advance":
            guard let yaml = mergedYAML, let s = yaml.asSeconds else {
                throw SpecParseError.invalidArgument("clock.advance needs a duration (e.g. 5s)", line: lineNumber)
            }
            return .clockAdvance(seconds: s)
        case "clock.set", "clock_set":
            guard case .object(let kvs)? = mergedYAML else {
                throw SpecParseError.invalidArgument("clock.set needs { iso8601, paused? }", line: lineNumber)
            }
            var iso: String?; var paused: Bool?
            for (k, v) in kvs {
                if k == "iso8601" { iso = v.asString }
                if k == "paused" { paused = v.asBool }
            }
            guard let iso else {
                throw SpecParseError.invalidArgument("clock.set needs iso8601", line: lineNumber)
            }
            return .clockSet(iso8601: iso, paused: paused)
        case "set_animations":
            // Form: set_animations: off  | on
            guard let v = mergedYAML else {
                throw SpecParseError.invalidArgument("set_animations needs on|off", line: lineNumber)
            }
            let s = v.asString?.lowercased() ?? "on"
            return .setAnimations(enabled: !(s == "off" || s == "false" || s == "no"))
        case "accept_sheet":
            // Form: accept_sheet: { button: "Save" }  or just accept_sheet (default button)
            if case .object(let kvs)? = mergedYAML {
                var btn: String?
                for (k, v) in kvs where k == "button" { btn = v.asString }
                return .acceptSheet(button: btn)
            }
            if let s = mergedYAML?.asString { return .acceptSheet(button: s) }
            return .acceptSheet(button: nil)
        case "dismiss_alert":
            return .dismissAlert
        case "select_menu":
            // Form: select_menu: "File > Open Recent > foo.pgn"  OR { path: [...] }
            if let s = mergedYAML?.asString {
                let parts = s.components(separatedBy: ">").map { $0.trimmingCharacters(in: .whitespaces) }
                return .selectMenu(path: parts)
            }
            if case .object(let kvs)? = mergedYAML, let p = kvs.first(where: { $0.0 == "path" })?.1, case .array(let arr) = p {
                return .selectMenu(path: arr.compactMap(\.asString))
            }
            throw SpecParseError.invalidArgument("select_menu needs a 'A > B > C' string or { path: [...] }", line: lineNumber)
        case "copy": return .copy
        case "paste": return .paste
        case "wait_for_idle":
            let timeout = mergedYAML?.asSeconds.map { Duration(seconds: $0) } ?? Duration(seconds: 2)
            return .waitForIdle(timeout: timeout)
        case "write_pasteboard":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("write_pasteboard needs a string", line: lineNumber)
            }
            return .writePasteboard(text: s)
        case "assert_pasteboard":
            // Form: assert_pasteboard: { contains: "..." }
            if case .object(let kvs)? = mergedYAML, let v = kvs.first(where: { $0.0 == "contains" })?.1, let s = v.asString {
                return .assertPasteboard(contains: s)
            }
            if let s = mergedYAML?.asString {
                return .assertPasteboard(contains: s)
            }
            throw SpecParseError.invalidArgument("assert_pasteboard needs contains:'...'", line: lineNumber)

        case "open_file":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("open_file needs an absolute file path string", line: lineNumber)
            }
            return .openFile(path: s)
        case "save_file":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("save_file needs an absolute file path string", line: lineNumber)
            }
            return .saveFile(path: s)
        case "panel_accept":
            if case .object(let kvs)? = mergedYAML {
                var btn: String?
                for (k, v) in kvs where k == "button" { btn = v.asString }
                return .panelAccept(button: btn)
            }
            if let s = mergedYAML?.asString { return .panelAccept(button: s) }
            return .panelAccept(button: nil)
        case "panel_cancel":
            return .panelCancel

        // Wave 2 — control flow
        case "if":
            return try buildIf(rhs: rhs, block: block, line: lineNumber)
        case "for":
            return try buildFor(rhs: rhs, block: block, line: lineNumber)
        case "repeat":
            return try buildRepeat(rhs: rhs, block: block, line: lineNumber)
        case "call":
            return try buildCall(mergedYAML, line: lineNumber)

        default:
            throw SpecParseError.unknownCommand(command, line: lineNumber)
        }
    }

    // MARK: - Wave 2 control-flow parsers

    private static func buildIf(rhs: String, block: [String], line: Int) throws -> Step {
        // Spec form:
        //   if: { visible: { id: "welcome" } }
        //     then:
        //       - dismiss_alert
        //       - click: { id: "ok" }
        //     else:
        //       - sleep: 100ms
        // For simplicity we accept a single-line form too:
        //   if: { visible: { id: "x" } } then: [ click: { ... } ]
        let yaml: YAMLValue
        if rhs.isEmpty && !block.isEmpty {
            yaml = try blockAsObject(block, line: line)
        } else if !rhs.isEmpty {
            // Treat rhs as the predicate; `then` and `else` come from indented lines.
            let pred = try YAMLFlow.parse(rhs)
            var kvs: [(String, YAMLValue)] = [("predicate", pred)]
            for kv in try parseListedSubBlocks(block, line: line) { kvs.append(kv) }
            yaml = .object(kvs)
        } else {
            throw SpecParseError.invalidArgument("if needs a predicate", line: line)
        }

        guard case .object(let kvs) = yaml else {
            throw SpecParseError.invalidArgument("if must be an object", line: line)
        }
        var pred: Predicate?
        var thenSteps: [Step] = []
        var elseSteps: [Step] = []
        for (k, v) in kvs {
            switch k {
            case "predicate": pred = try parsePredicate(v, line: line)
            case "then": thenSteps = try parseStepsList(v, line: line)
            case "else": elseSteps = try parseStepsList(v, line: line)
            default:
                if pred == nil { pred = try parsePredicate(.object([(k, v)]), line: line) }
            }
        }
        guard let pred else {
            throw SpecParseError.invalidArgument("if needs a predicate", line: line)
        }
        return .if(predicate: pred, then: thenSteps, else: elseSteps)
    }

    private static func buildFor(rhs: String, block: [String], line: Int) throws -> Step {
        // for: { var: "move", in: ["e4", "e5", "Nf3"] }
        //   - click: { id: "${move}" }
        let yaml: YAMLValue
        if !rhs.isEmpty { yaml = try YAMLFlow.parse(rhs) }
        else { yaml = try blockAsObject(block, line: line) }

        guard case .object(let kvs) = yaml else {
            throw SpecParseError.invalidArgument("for needs an object", line: line)
        }
        var varName: String?; var items: [YAMLValue] = []; var bodyVal: YAMLValue?
        for (k, v) in kvs {
            if k == "var" { varName = v.asString }
            if k == "in", case .array(let arr) = v { items = arr }
            if k == "do" { bodyVal = v }
        }
        guard let varName else {
            throw SpecParseError.invalidArgument("for needs `var`", line: line)
        }
        let bodySteps: [Step]
        if let bodyVal {
            bodySteps = try parseStepsList(bodyVal, line: line)
        } else {
            // Indented sub-block (after the head line, lines starting with `-`)
            bodySteps = try parseDashedSteps(block, line: line)
        }
        return .forEach(varName: varName, items: items, body: bodySteps)
    }

    private static func buildRepeat(rhs: String, block: [String], line: Int) throws -> Step {
        // repeat: 5
        //   - click: { id: "btn" }
        let count: Int
        if !rhs.isEmpty, let n = (try? YAMLFlow.parse(rhs))?.asInt { count = n }
        else { throw SpecParseError.invalidArgument("repeat needs an integer count", line: line) }
        let body = try parseDashedSteps(block, line: line)
        return .repeatN(count: count, body: body)
    }

    private static func buildCall(_ yaml: YAMLValue?, line: Int) throws -> Step {
        // call: my_flow
        // call: { name: my_flow, args: { x: 1 } }
        if let s = yaml?.asString { return .callFlow(name: s, args: [:]) }
        if case .object(let kvs)? = yaml {
            var name: String?
            var args: [String: YAMLValue] = [:]
            for (k, v) in kvs {
                if k == "name" { name = v.asString }
                if k == "args", case .object(let argKVs) = v {
                    for (ak, av) in argKVs { args[ak] = av }
                }
            }
            guard let name else {
                throw SpecParseError.invalidArgument("call needs a flow name", line: line)
            }
            return .callFlow(name: name, args: args)
        }
        throw SpecParseError.invalidArgument("call needs a flow name", line: line)
    }

    /// Parse a `then:` / `else:` value as a list of steps. Accepts either a
    /// YAML array of inline-flow step objects, or an indented dash-list.
    private static func parseStepsList(_ yaml: YAMLValue, line: Int) throws -> [Step] {
        if case .array(let arr) = yaml {
            return try arr.map { item -> Step in
                guard case .object(let kvs) = item, let (verb, arg) = kvs.first else {
                    throw SpecParseError.invalidArgument("step must be a single-verb object", line: line)
                }
                let head = "\(verb): " + renderInlineYAML(arg)
                return try parseStep(head, block: [], lineNumber: line)
            }
        }
        return []
    }

    /// Parse indented dash-prefixed lines as a list of Steps.
    /// Example block:
    ///     - click: { id: "a" }
    ///     - assert_state: { ... }
    private static func parseDashedSteps(_ block: [String], line: Int) throws -> [Step] {
        var steps: [Step] = []
        for raw in block {
            let s = raw.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("- ") else { continue }
            let head = String(s.dropFirst(2))
            steps.append(try parseStep(head, block: [], lineNumber: line))
        }
        return steps
    }

    private static func parseListedSubBlocks(_ block: [String], line: Int) throws -> [(String, YAMLValue)] {
        // Currently a no-op extender — used for `if: <rhs>` followed by `then:` / `else:`.
        var kvs: [(String, YAMLValue)] = []
        for raw in block {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if let colon = s.firstIndex(of: ":") {
                let k = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty {
                    if let yaml = try? YAMLFlow.parse(v) { kvs.append((k, yaml)) }
                }
            }
        }
        return kvs
    }

    private static func blockAsObject(_ block: [String], line: Int) throws -> YAMLValue {
        var kvs: [(String, YAMLValue)] = []
        for raw in block {
            let s = raw.trimmingCharacters(in: .whitespaces)
            if let colon = s.firstIndex(of: ":") {
                let k = String(s[..<colon]).trimmingCharacters(in: .whitespaces)
                let v = String(s[s.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
                if !v.isEmpty {
                    let val = (try? YAMLFlow.parse(v)) ?? .string(v)
                    kvs.append((k, val))
                }
            }
        }
        return .object(kvs)
    }

    private static func renderInlineYAML(_ v: YAMLValue) -> String {
        switch v {
        case .string(let s): return "\"\(s)\""
        case .identifier(let s): return s
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        case .null: return "null"
        case .duration(let s): return "\(s)s"
        case .array(let arr): return "[\(arr.map(renderInlineYAML).joined(separator: ", "))]"
        case .object(let kvs):
            return "{\(kvs.map { "\($0.0): \(renderInlineYAML($0.1))" }.joined(separator: ", "))}"
        }
    }

    private static func buildExpectChange(_ kvs: [(String, YAMLValue)], line: Int) throws -> Step {
        var actionYAML: YAMLValue?
        var inObs: YAMLValue?
        var toValue: YAMLValue?
        var timeout: Duration = Duration(seconds: 2)
        for (k, v) in kvs {
            switch k {
            case "action": actionYAML = v
            case "in": inObs = v
            case "to": toValue = v
            case "timeout": if let s = v.asSeconds { timeout = Duration(seconds: s) }
            default: break
            }
        }
        guard let actionYAML, case .object(let actionKVs) = actionYAML, let (verb, arg) = actionKVs.first else {
            throw SpecParseError.invalidArgument("expect_change.action must be a single-verb object like { click: { id: ... } }", line: line)
        }
        let action: ExpectChangeAction
        switch verb {
        case "click": action = .click(try parseTarget(arg, line: line))
        case "double_click": action = .doubleClick(try parseTarget(arg, line: line))
        case "right_click": action = .rightClick(try parseTarget(arg, line: line))
        case "key":
            guard let s = arg.asString else {
                throw SpecParseError.invalidArgument("expect_change.action.key needs a combo string", line: line)
            }
            action = .key(s)
        case "type":
            guard let s = arg.asString else {
                throw SpecParseError.invalidArgument("expect_change.action.type needs a string", line: line)
            }
            action = .type(s)
        default:
            throw SpecParseError.invalidArgument("expect_change.action verb '\(verb)' not allowed (use click/double_click/right_click/key/type)", line: line)
        }
        guard case .object(let obsKVs)? = inObs else {
            throw SpecParseError.invalidArgument("expect_change.in must be { viewmodel, path }", line: line)
        }
        var vm: String?
        var path: String?
        for (k, v) in obsKVs {
            if k == "viewmodel" { vm = v.asString }
            if k == "path" { path = v.asString }
        }
        guard let vm, let path else {
            throw SpecParseError.invalidArgument("expect_change.in needs viewmodel and path", line: line)
        }
        guard let toValue else {
            throw SpecParseError.invalidArgument("expect_change needs `to`", line: line)
        }
        return .expectChange(action: action, viewmodel: vm, path: path, to: toValue, timeout: timeout)
    }

    private static func buildAssertState(_ kvs: [(String, YAMLValue)], line: Int) throws -> Step {
        var vm: String?
        var path: String?
        var expect: StateExpectation?
        for (k, v) in kvs {
            switch k {
            case "viewmodel": vm = v.asString
            case "path": path = v.asString
            case "equals": expect = .equals(v)
            case "matches":
                if let s = v.asString { expect = .matches(s) }
            case "any_of":
                if case .array(let arr) = v { expect = .anyOf(arr) }
            default: break
            }
        }
        guard let vm, let path else {
            throw SpecParseError.invalidArgument("assert_state missing viewmodel or path", line: line)
        }
        guard let expect else {
            throw SpecParseError.invalidArgument("assert_state missing equals/matches/any_of", line: line)
        }
        return .assertState(viewmodel: vm, path: path, expect: expect)
    }

    // MARK: - Target / Predicate parsing

    /// Like parseTarget but also extracts a `modifiers: [shift, cmd]` array from
    /// the same object. Returns the target plus the modifier tokens.
    static func parseTargetWithModifiers(_ yaml: YAMLValue?, line: Int) throws -> (TargetRef, [String]) {
        let target = try parseTarget(yaml, line: line)
        var mods: [String] = []
        if case .object(let kvs)? = yaml {
            for (k, v) in kvs where k == "modifiers" {
                if case .array(let arr) = v { mods = arr.compactMap(\.asString) }
            }
        }
        return (target, mods)
    }

    static func parsePointSpec(_ kvs: [(String, YAMLValue)]) -> PointSpec? {
        var x: Double?; var y: Double?
        for (k, v) in kvs {
            if k == "x" { x = (v.asInt.map(Double.init)) ?? v.asSeconds }
            if k == "y" { y = (v.asInt.map(Double.init)) ?? v.asSeconds }
        }
        guard let x, let y else { return nil }
        return PointSpec(x: x, y: y)
    }

    static func parseTarget(_ yaml: YAMLValue?, line: Int) throws -> TargetRef {
        guard case .object(let kvs)? = yaml else {
            throw SpecParseError.invalidArgument("target must be an object", line: line)
        }
        var map: [String: YAMLValue] = [:]
        for (k, v) in kvs { map[k] = v }

        if let id = map["id"]?.asString { return .id(id) }
        if let role = map["role"]?.asString, let label = map["label"]?.asString {
            return .roleLabel(role: role, label: label)
        }
        if let label = map["label"]?.asString { return .label(label) }
        if let lm = map["label_matches"]?.asString { return .labelMatches(lm) }
        if let tp = map["tree_path"]?.asString { return .treePath(tp) }
        if case .object(let pkvs)? = map["point"] {
            var x: Double?; var y: Double?
            for (k, v) in pkvs {
                if k == "x" { x = v.asSeconds ?? Double(v.asInt ?? 0) }
                if k == "y" { y = v.asSeconds ?? Double(v.asInt ?? 0) }
            }
            if let x, let y { return .point(x: x, y: y) }
        }
        throw SpecParseError.invalidArgument("target has no recognized form (id / role+label / label / label_matches / tree_path / point)", line: line)
    }

    static func parsePredicate(_ yaml: YAMLValue, line: Int) throws -> Predicate {
        guard case .object(let kvs) = yaml else {
            throw SpecParseError.invalidArgument("predicate must be an object", line: line)
        }

        // Window-shortcut: { role: Window, title_matches: "..." } or { role: Window, title: "..." }
        let roleIsWindow = kvs.contains(where: { $0.0 == "role" && $0.1.asString == "Window" })
        if roleIsWindow {
            var title: String?
            var titleMatches: String?
            for (k, v) in kvs {
                if k == "title" { title = v.asString }
                if k == "title_matches" { titleMatches = v.asString }
            }
            return .window(title: title, titleMatches: titleMatches)
        }

        // Delegate by key.
        for (k, v) in kvs {
            switch k {
            case "contains":
                let t = try parseTarget(v, line: line)
                return .contains(t)
            case "not_contains":
                let t = try parseTarget(v, line: line)
                return .notContains(t)
            case "count":
                if case .object(let ckvs) = v {
                    var ofTarget: TargetRef? = nil
                    var count: Int? = nil
                    for (kk, vv) in ckvs {
                        if kk == "of" { ofTarget = try? parseTarget(vv, line: line) }
                        if kk == "equals" { count = vv.asInt }
                    }
                    if let ofTarget, let count { return .countOf(ofTarget, equals: count) }
                }
                throw SpecParseError.invalidArgument("count needs { of: <target>, equals: N }", line: line)
            case "visible":
                return .visible(try parseTarget(v, line: line))
            case "enabled":
                return .enabled(try parseTarget(v, line: line))
            case "focused":
                return .focused(try parseTarget(v, line: line))
            case "state":
                if case .object(let skvs) = v {
                    return try .state(viewmodel: requireString(skvs, "viewmodel", line: line),
                                      path: requireString(skvs, "path", line: line),
                                      expect: try parseExpectation(from: skvs, line: line))
                }
                throw SpecParseError.invalidArgument("state predicate needs viewmodel/path/equals", line: line)
            case "all_of":
                if case .array(let arr) = v {
                    return .allOf(try arr.map { try parsePredicate($0, line: line) })
                }
                throw SpecParseError.invalidArgument("all_of needs an array", line: line)
            case "any_of":
                if case .array(let arr) = v {
                    return .anyOf(try arr.map { try parsePredicate($0, line: line) })
                }
                throw SpecParseError.invalidArgument("any_of needs an array", line: line)
            case "not":
                return .not(try parsePredicate(v, line: line))
            default:
                continue
            }
        }

        // Fallback: treat the object as a bare target and wrap in `contains`.
        let t = try parseTarget(yaml, line: line)
        return .contains(t)
    }

    private static func parseExpectation(from kvs: [(String, YAMLValue)], line: Int) throws -> StateExpectation {
        for (k, v) in kvs {
            switch k {
            case "equals": return .equals(v)
            case "matches":
                if let s = v.asString { return .matches(s) }
            case "any_of":
                if case .array(let arr) = v { return .anyOf(arr) }
            default: continue
            }
        }
        throw SpecParseError.invalidArgument("state predicate needs equals / matches / any_of", line: line)
    }

    private static func requireString(_ kvs: [(String, YAMLValue)], _ key: String, line: Int) throws -> String {
        for (k, v) in kvs where k == key { if let s = v.asString { return s } }
        throw SpecParseError.invalidArgument("missing '\(key)'", line: line)
    }
}
