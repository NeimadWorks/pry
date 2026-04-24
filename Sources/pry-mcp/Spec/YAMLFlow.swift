import Foundation

/// Tiny parser for YAML flow-style values as used in Pry spec `pry` blocks.
/// Handles a JSON-like subset with unquoted identifier keys and bare scalars.
///
/// Supported:
///   - Strings: "..." or '...' (with \n \t \" \\ escapes)
///   - Integers: -?[0-9]+
///   - Doubles: -?[0-9]+\.[0-9]+ (optional exponent)
///   - Bools: true / false
///   - null
///   - Bare identifiers (used as enum-like values): `Button`, `up`, `shift+cmd+n`
///   - Durations: 2s, 100ms, 5min — stored as .duration(seconds:)
///   - Objects: { k: v, k: "v", k: 42 }  (unquoted keys allowed)
///   - Arrays: [ a, b, "c", 42 ]
///   - Nested freely.
///
/// Not supported: YAML anchors, merge keys, multi-line scalars, flow flow-split,
/// any YAML extension Pry specs don't need.
public indirect enum YAMLValue: Sendable, Equatable {
    case string(String)
    case integer(Int)
    case double(Double)
    case bool(Bool)
    case null
    case identifier(String)    // bare word (not "true"/"false"/"null")
    case duration(seconds: Double)
    case array([YAMLValue])
    case object([(String, YAMLValue)])

    public static func == (lhs: YAMLValue, rhs: YAMLValue) -> Bool {
        switch (lhs, rhs) {
        case (.string(let a), .string(let b)): return a == b
        case (.integer(let a), .integer(let b)): return a == b
        case (.double(let a), .double(let b)): return a == b
        case (.bool(let a), .bool(let b)): return a == b
        case (.null, .null): return true
        case (.identifier(let a), .identifier(let b)): return a == b
        case (.duration(let a), .duration(let b)): return a == b
        case (.array(let a), .array(let b)): return a == b
        case (.object(let a), .object(let b)):
            return a.count == b.count && zip(a, b).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
        default: return false
        }
    }
}

public extension YAMLValue {
    /// Coerce to a Swift string regardless of backing case. Useful when both
    /// `"hello"` and `hello` should work.
    var asString: String? {
        switch self {
        case .string(let s): return s
        case .identifier(let s): return s
        case .integer(let i): return String(i)
        case .double(let d): return String(d)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    var asInt: Int? {
        switch self {
        case .integer(let i): return i
        case .double(let d): return Int(d)
        case .string(let s): return Int(s)
        default: return nil
        }
    }

    var asBool: Bool? {
        if case .bool(let b) = self { return b }
        return nil
    }

    var asSeconds: Double? {
        if case .duration(let s) = self { return s }
        if case .integer(let i) = self { return Double(i) }
        if case .double(let d) = self { return d }
        return nil
    }

    var asObject: [(String, YAMLValue)]? {
        if case .object(let kvs) = self { return kvs }
        return nil
    }

    var asArray: [YAMLValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    subscript(key: String) -> YAMLValue? {
        guard case .object(let kvs) = self else { return nil }
        return kvs.first(where: { $0.0 == key })?.1
    }
}

// MARK: - Parser

public enum YAMLFlowError: Error, CustomStringConvertible {
    case unexpectedToken(String, at: Int)
    case unterminatedString(at: Int)
    case invalidDuration(String)
    case trailingContent(String)
    case empty

    public var description: String {
        switch self {
        case .unexpectedToken(let s, let i): return "unexpected token '\(s)' at \(i)"
        case .unterminatedString(let i): return "unterminated string starting at \(i)"
        case .invalidDuration(let s): return "invalid duration: '\(s)'"
        case .trailingContent(let s): return "trailing content after value: '\(s)'"
        case .empty: return "empty input"
        }
    }
}

public enum YAMLFlow {
    public static func parse(_ text: String) throws -> YAMLValue {
        var parser = Parser(source: text)
        parser.skipWhitespace()
        guard !parser.atEnd else { throw YAMLFlowError.empty }
        let value = try parser.parseValue()
        parser.skipWhitespace()
        if !parser.atEnd {
            throw YAMLFlowError.trailingContent(String(parser.source[parser.pos...]))
        }
        return value
    }
}

private struct Parser {
    let source: String
    var pos: String.Index

    init(source: String) {
        self.source = source
        self.pos = source.startIndex
    }

    var atEnd: Bool { pos >= source.endIndex }
    var peek: Character? { atEnd ? nil : source[pos] }

    mutating func advance() { pos = source.index(after: pos) }

    mutating func skipWhitespace() {
        while !atEnd, source[pos].isWhitespace { advance() }
    }

    mutating func parseValue() throws -> YAMLValue {
        skipWhitespace()
        guard let c = peek else { throw YAMLFlowError.empty }
        switch c {
        case "{": return try parseObject()
        case "[": return try parseArray()
        case "\"", "'": return .string(try parseQuotedString())
        case "-", "0"..."9": return try parseNumberOrDuration()
        default: return try parseIdentOrKeyword()
        }
    }

    mutating func parseObject() throws -> YAMLValue {
        advance() // {
        var entries: [(String, YAMLValue)] = []
        skipWhitespace()
        if peek == "}" { advance(); return .object(entries) }

        while true {
            skipWhitespace()
            let key: String
            if peek == "\"" || peek == "'" {
                key = try parseQuotedString()
            } else {
                key = try parseBareIdentifier()
            }
            skipWhitespace()
            guard peek == ":" else {
                throw YAMLFlowError.unexpectedToken(String(peek ?? " "), at: sourceOffset())
            }
            advance()
            let value = try parseValue()
            entries.append((key, value))
            skipWhitespace()
            if peek == "," { advance(); continue }
            if peek == "}" { advance(); return .object(entries) }
            throw YAMLFlowError.unexpectedToken(String(peek ?? " "), at: sourceOffset())
        }
    }

    mutating func parseArray() throws -> YAMLValue {
        advance() // [
        var items: [YAMLValue] = []
        skipWhitespace()
        if peek == "]" { advance(); return .array(items) }

        while true {
            items.append(try parseValue())
            skipWhitespace()
            if peek == "," { advance(); continue }
            if peek == "]" { advance(); return .array(items) }
            throw YAMLFlowError.unexpectedToken(String(peek ?? " "), at: sourceOffset())
        }
    }

    mutating func parseQuotedString() throws -> String {
        let start = sourceOffset()
        let quote = source[pos]
        advance()
        var out = ""
        while !atEnd {
            let c = source[pos]
            if c == quote {
                advance()
                return out
            }
            if c == "\\" {
                advance()
                if atEnd { throw YAMLFlowError.unterminatedString(at: start) }
                switch source[pos] {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "r": out.append("\r")
                case "\"": out.append("\"")
                case "'": out.append("'")
                case "\\": out.append("\\")
                default: out.append(source[pos])
                }
                advance()
                continue
            }
            out.append(c)
            advance()
        }
        throw YAMLFlowError.unterminatedString(at: start)
    }

    mutating func parseNumberOrDuration() throws -> YAMLValue {
        let start = pos
        if peek == "-" { advance() }
        while !atEnd, source[pos].isNumber { advance() }
        var isDouble = false
        if peek == "." {
            isDouble = true
            advance()
            while !atEnd, source[pos].isNumber { advance() }
        }
        // Exponent
        if peek == "e" || peek == "E" {
            isDouble = true
            advance()
            if peek == "+" || peek == "-" { advance() }
            while !atEnd, source[pos].isNumber { advance() }
        }
        let numericStr = String(source[start..<pos])

        // Duration suffix?
        if let c = peek, c.isLetter {
            let unitStart = pos
            while !atEnd, source[pos].isLetter { advance() }
            let unit = String(source[unitStart..<pos])
            let base = Double(numericStr) ?? 0
            switch unit {
            case "s": return .duration(seconds: base)
            case "ms": return .duration(seconds: base / 1000.0)
            case "min": return .duration(seconds: base * 60)
            default:
                // Not a duration unit; treat the numeric part as number and the rest
                // as malformed. Roll back the unit consumption.
                pos = unitStart
                if isDouble {
                    return .double(Double(numericStr) ?? 0)
                } else {
                    return .integer(Int(numericStr) ?? 0)
                }
            }
        }

        if isDouble {
            return .double(Double(numericStr) ?? 0)
        } else {
            return .integer(Int(numericStr) ?? 0)
        }
    }

    mutating func parseIdentOrKeyword() throws -> YAMLValue {
        let ident = try parseBareIdentifier()
        switch ident {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null", "~": return .null
        default: return .identifier(ident)
        }
    }

    mutating func parseBareIdentifier() throws -> String {
        let start = pos
        let allowed: (Character) -> Bool = { c in
            c.isLetter || c.isNumber || c == "_" || c == "-" || c == "." || c == "+" || c == "/"
        }
        while !atEnd, allowed(source[pos]) { advance() }
        if pos == start {
            throw YAMLFlowError.unexpectedToken(String(peek ?? " "), at: sourceOffset())
        }
        return String(source[start..<pos])
    }

    private func sourceOffset() -> Int {
        source.distance(from: source.startIndex, to: pos)
    }
}
