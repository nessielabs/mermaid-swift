/// Parses the relaxed JSON accepted by Mermaid directives: single or
/// double quoted strings, unquoted keys, and trailing commas.
enum LenientJSON {
    static func parse(_ text: String, at start: SourceLocation = .start) throws -> ConfigValue {
        var scanner = Scanner(text, at: start)
        let value = try parseValue(&scanner)
        scanner.skipWhitespace(newlines: true)
        guard scanner.isAtEnd else {
            throw MermaidError(.configuration, "Unexpected text after configuration value", at: scanner.location)
        }
        return value
    }

    private static func parseValue(_ s: inout Scanner) throws -> ConfigValue {
        s.skipWhitespace(newlines: true)
        switch s.peek() {
        case "{": return try parseObject(&s)
        case "[": return try parseArray(&s)
        case "\"", "'": return .string(try parseString(&s))
        case nil: throw MermaidError(.configuration, "Expected a value", at: s.location)
        default:
            let word = s.read { !",}]:\n".contains($0) }.trimmingWhitespace()
            switch word {
            case "true": return .bool(true)
            case "false": return .bool(false)
            case "null": return .null
            default: return Double(word).map(ConfigValue.number) ?? .string(word)
            }
        }
    }

    private static func parseObject(_ s: inout Scanner) throws -> ConfigValue {
        s.advance()
        var dict: [String: ConfigValue] = [:]
        while true {
            s.skipWhitespace(newlines: true)
            if s.consume("}") { return .object(dict) }
            let key: String
            if s.peek() == "\"" || s.peek() == "'" {
                key = try parseString(&s)
            } else {
                key = s.read { $0 != ":" && $0 != "}" && $0 != "\n" }.trimmingWhitespace()
            }
            s.skipWhitespace(newlines: true)
            try s.expectConfig(":", "Expected ':' after key '\(key)'")
            dict[key] = try parseValue(&s)
            s.skipWhitespace(newlines: true)
            if s.consume(",") { continue }
            try s.expectConfig("}", "Expected ',' or '}' in object")
            return .object(dict)
        }
    }

    private static func parseArray(_ s: inout Scanner) throws -> ConfigValue {
        s.advance()
        var items: [ConfigValue] = []
        while true {
            s.skipWhitespace(newlines: true)
            if s.consume("]") { return .array(items) }
            items.append(try parseValue(&s))
            s.skipWhitespace(newlines: true)
            if s.consume(",") { continue }
            try s.expectConfig("]", "Expected ',' or ']' in array")
            return .array(items)
        }
    }

    static func parseString(_ s: inout Scanner) throws -> String {
        let start = s.location
        guard let quote = s.advance() else { throw MermaidError(.configuration, "Expected a string", at: start) }
        var result = ""
        while let c = s.advance() {
            if c == quote { return result }
            if c == "\\", let escaped = s.advance() {
                switch escaped {
                case "n": result.append("\n")
                case "t": result.append("\t")
                default: result.append(escaped)
                }
            } else {
                result.append(c)
            }
        }
        throw MermaidError(.configuration, "Unterminated string", at: start)
    }
}

private extension Scanner {
    mutating func expectConfig(_ text: String, _ message: String) throws {
        guard consume(text) else { throw MermaidError(.configuration, message, at: location) }
    }
}
