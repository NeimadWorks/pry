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

        // 2. Extract all ```pry fenced blocks with their starting line numbers.
        let blocks = try extractPryBlocks(body: body)

        // 3. For each block, tokenize lines into Steps.
        var steps: [Step] = []
        for (block, startLine) in blocks {
            steps.append(contentsOf: try parseBlock(block, startLine: startLine))
        }

        return Spec(
            id: fm.id,
            app: fm.app,
            description: fm.description,
            tags: fm.tags ?? [],
            timeout: fm.timeout ?? .defaultSpec,
            executablePath: fm.executablePath,
            sourcePath: sourcePath,
            steps: steps,
            sourceText: source
        )
    }

    // MARK: - Frontmatter

    private struct Frontmatter {
        var id: String
        var app: String
        var description: String?
        var tags: [String]?
        var timeout: Duration?
        var executablePath: String?
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

        return fm
    }

    private static func unquote(_ s: String) -> String {
        guard s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" else { return s }
        return String(s.dropFirst().dropLast())
    }

    // MARK: - Block extraction

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
            return .click(target: try parseTarget(mergedYAML, line: lineNumber))
        case "double_click":
            return .doubleClick(target: try parseTarget(mergedYAML, line: lineNumber))
        case "right_click":
            return .rightClick(target: try parseTarget(mergedYAML, line: lineNumber))
        case "hover":
            return .hover(target: try parseTarget(mergedYAML, line: lineNumber))
        case "type":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("type needs a string", line: lineNumber)
            }
            return .type(text: s)
        case "key":
            guard let s = mergedYAML?.asString else {
                throw SpecParseError.invalidArgument("key needs a combo string", line: lineNumber)
            }
            return .key(combo: s)

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

        default:
            throw SpecParseError.unknownCommand(command, line: lineNumber)
        }
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
