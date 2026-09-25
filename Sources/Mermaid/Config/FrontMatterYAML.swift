import Foundation


/// Reads the YAML subset used by Mermaid front matter: nested mappings by
/// indentation, block and flow sequences, and plain, quoted, or flow
/// (`{...}` / `[...]`) scalars. Anything richer is rejected with a
/// configuration error rather than silently misread.
enum FrontMatterYAML {
    static func parse(_ lines: [SourceLine]) throws -> ConfigValue {
        var index = 0
        return try parseBlock(lines, &index, indent: lines.first?.indent ?? 0)
    }

    private static func parseBlock(_ lines: [SourceLine], _ index: inout Int, indent: Int) throws -> ConfigValue {
        guard index < lines.count else { return .null }
        if lines[index].text.hasPrefix("- ") || lines[index].text == "-" {
            return try parseSequence(lines, &index, indent: indent)
        }
        var dict: [String: ConfigValue] = [:]
        while index < lines.count, lines[index].indent == indent {
            let line = lines[index]
            guard let (rawKey, rawValue) = line.text.splitOnce(":") else {
                throw MermaidError(.configuration, "Expected 'key: value' in front matter", at: line.location)
            }
            let key = unquote(rawKey.trimmingWhitespace())
            let value = rawValue.trimmingWhitespace()
            index += 1
            if value.isEmpty {
                if index < lines.count, lines[index].indent > indent {
                    dict[key] = try parseBlock(lines, &index, indent: lines[index].indent)
                } else {
                    dict[key] = .null
                }
            } else {
                dict[key] = try scalar(value, at: line.location(atOffset: rawKey.count + 1))
            }
        }
        if index < lines.count, lines[index].indent > indent {
            throw MermaidError(.configuration, "Unexpected indentation in front matter", at: lines[index].location)
        }
        return .object(dict)
    }

    private static func parseSequence(_ lines: [SourceLine], _ index: inout Int, indent: Int) throws -> ConfigValue {
        var items: [ConfigValue] = []
        while index < lines.count, lines[index].indent == indent, lines[index].text.hasPrefix("-") {
            let line = lines[index]
            let item = String(line.text.dropFirst()).trimmingWhitespace()
            index += 1
            if item.isEmpty, index < lines.count, lines[index].indent > indent {
                items.append(try parseBlock(lines, &index, indent: lines[index].indent))
            } else {
                items.append(try scalar(item, at: line.location(atOffset: 2)))
            }
        }
        return .array(items)
    }

    private static func scalar(_ text: String, at location: SourceLocation) throws -> ConfigValue {
        let text = stripComment(text)
        if text.hasPrefix("{") || text.hasPrefix("[") {
            return try LenientJSON.parse(text, at: location)
        }
        if text.hasPrefix("\"") || text.hasPrefix("'") {
            return .string(unquote(text))
        }
        switch text.lowercased() {
        case "true", "yes", "on": return .bool(true)
        case "false", "no", "off": return .bool(false)
        case "null", "~": return .null
        default: return Double(text).map(ConfigValue.number) ?? .string(text)
        }
    }

    private static func stripComment(_ text: String) -> String {
        guard !text.hasPrefix("\""), !text.hasPrefix("'"), let r = text.range(of: " #") else { return text }
        return String(text[..<r.lowerBound]).trimmingWhitespace()
    }

    private static func unquote(_ text: String) -> String {
        guard text.count >= 2, let first = text.first, first == text.last, first == "\"" || first == "'" else {
            return text
        }
        return String(text.dropFirst().dropLast())
    }
}
