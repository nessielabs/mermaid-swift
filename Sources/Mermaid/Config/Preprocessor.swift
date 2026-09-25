import Foundation

/// Diagram source after front matter, directives, and comments have been
/// extracted. `body` keeps its original line numbering: extracted regions
/// are replaced with blank lines so diagnostics still line up.
struct PreparedSource: Sendable {
    var body: String
    var title: String?
    /// Configuration from front matter `config:` merged with `init`
    /// directives, in source order.
    var config: ConfigValue
    /// The first statement of the body, which declares the diagram type.
    var header: SourceLine?
}

enum Preprocessor {
    static func prepare(_ source: String) throws -> PreparedSource {
        var lines = source
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)

        var title: String?
        var config = ConfigValue.object([:])
        if let (front, range) = try extractFrontMatter(lines) {
            title = front["title"]?.stringValue
            if let frontConfig = front["config"] { config = config.merging(frontConfig) }
            for i in range { lines[i] = "" }
        }
        for directive in try extractDirectives(&lines) {
            config = config.merging(directive)
        }
        for i in lines.indices where lines[i].trimmingWhitespace().hasPrefix("%%") {
            lines[i] = ""
        }
        let body = lines.joined(separator: "\n")
        return PreparedSource(body: body, title: title, config: config, header: SourceLine.split(body).first)
    }

    private static func extractFrontMatter(_ lines: [String]) throws -> (ConfigValue, ClosedRange<Int>)? {
        guard let open = lines.firstIndex(where: { !$0.trimmingWhitespace().isEmpty }),
              lines[open].trimmingWhitespace() == "---" else { return nil }
        guard let close = lines[(open + 1)...].firstIndex(where: { $0.trimmingWhitespace() == "---" }) else {
            throw MermaidError(.configuration, "Front matter is missing its closing '---'",
                               at: SourceLocation(line: open + 1, column: 1))
        }
        let yaml = lines[(open + 1)..<close].joined(separator: "\n")
        let value = try FrontMatterYAML.parse(SourceLine.split(yaml, firstLine: open + 2))
        return (value, open...close)
    }

    /// Removes every `%%{ ... }%%` directive (which may span lines) and
    /// returns the configuration objects they declare.
    private static func extractDirectives(_ lines: inout [String]) throws -> [ConfigValue] {
        var configs: [ConfigValue] = []
        var i = 0
        while i < lines.count {
            guard let open = lines[i].range(of: "%%{") else { i += 1; continue }
            var text = String(lines[i][open.upperBound...])
            var end = i
            while text.range(of: "}%%") == nil, end + 1 < lines.count {
                end += 1
                text += "\n" + lines[end]
            }
            guard let close = text.range(of: "}%%", options: .backwards) else {
                throw MermaidError(.configuration, "Directive is missing its closing '}%%'",
                                   at: SourceLocation(line: i + 1, column: 1))
            }
            let inner = String(text[..<close.lowerBound])
            if let config = try directiveConfig(inner, at: SourceLocation(line: i + 1, column: 1)) {
                configs.append(config)
            }
            lines[i] = String(lines[i][..<open.lowerBound])
            for j in (i + 1)..<(end + 1) where j > i { lines[j] = "" }
            i = end + 1
        }
        return configs
    }

    private static func directiveConfig(_ inner: String, at location: SourceLocation) throws -> ConfigValue? {
        let trimmed = inner.trimmingWhitespace()
        if trimmed == "wrap" { return .object(["wrap": .bool(true)]) }
        guard let (name, rest) = trimmed.splitOnce(":") else { return nil }
        switch name.trimmingWhitespace().lowercased() {
        case "init", "initialize":
            return try LenientJSON.parse(rest.trimmingWhitespace(), at: location)
        default:
            return nil
        }
    }
}
