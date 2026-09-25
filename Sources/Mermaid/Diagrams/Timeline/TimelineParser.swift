/// Parses timeline source into a `TimelineDiagram`.
///
/// Each line is a `title`, a `section`, a time period followed by
/// `: event` items, or a continuation line of `: event` items for the
/// previous period. As in mermaid.js, an event separator is a colon
/// followed by whitespace, so events may contain times such as `10:30`.
enum TimelineParser {
    static func parse(_ source: DiagramSource) throws -> TimelineDiagram {
        var diagram = TimelineDiagram()
        diagram.accessibility = source.accessibility
        let argument = source.headerArguments
        switch argument.uppercased() {
        case "": break
        case "LR": diagram.direction = .leftToRight
        case "TD", "TB": diagram.direction = .topToBottom
        default:
            throw MermaidError.syntax("Unknown timeline direction '\(argument)'; use LR or TD",
                                      at: source.header.location(atOffset: 9))
        }

        // `#` starts a comment outside event text, as in mermaid's lexer.
        for line in source.lines where !line.text.hasPrefix("#") {
            let keyword = String(line.text.prefix { !$0.isWhitespace }).lowercased()
            let rest = line.text.dropFirst(keyword.count)
            let hasArgument = rest.first?.isWhitespace == true && !rest.trimmingWhitespace().isEmpty
            if keyword == "title", hasArgument {
                diagram.title = rest.trimmingWhitespace()
                continue
            }
            var parts = split(line.text)
            if keyword == "section", hasArgument {
                // A section title ends at the first colon.
                let name = String(line.text.dropFirst(keyword.count).prefix { $0 != ":" }).trimmingWhitespace()
                diagram.sections.append(name)
                guard line.text.contains(":") else { continue }
                parts[0] = ""
            }
            let period = String(parts[0].prefix { $0 != "#" }).trimmingWhitespace()
            let events = parts.dropFirst().map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
            if !period.isEmpty {
                let section = diagram.sections.isEmpty ? nil : diagram.sections.count - 1
                diagram.periods.append(TimelineDiagram.Period(text: period, events: events, section: section))
            } else if !events.isEmpty {
                guard !diagram.periods.isEmpty else {
                    throw MermaidError.syntax("Events need a time period before them", at: line.location)
                }
                diagram.periods[diagram.periods.count - 1].events += events
            }
        }
        return diagram
    }

    /// Splits a line at each colon followed by whitespace or the end of
    /// the line; the first part is the period.
    static func split(_ text: String) -> [String] {
        var parts = [""]
        let chars = Array(text)
        for (i, c) in chars.enumerated() {
            if c == ":", i + 1 == chars.count || chars[i + 1].isWhitespace {
                parts.append("")
            } else {
                parts[parts.count - 1].append(c)
            }
        }
        return parts
    }
}
