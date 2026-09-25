/// Parses user journey source into a `JourneyDiagram`.
///
/// Statements are `title`, `section`, and tasks written as
/// `name: score: actor, actor`. As in mermaid.js' lexer, `#` and `;`
/// end a statement.
enum JourneyParser {
    static func parse(_ source: DiagramSource) throws -> JourneyDiagram {
        var diagram = JourneyDiagram()
        diagram.accessibility = source.accessibility
        for line in source.lines {
            let text = String(line.text.prefix { $0 != "#" && $0 != ";" }).trimmingWhitespace()
            guard !text.isEmpty else { continue }
            let keyword = String(text.prefix { !$0.isWhitespace }).lowercased()
            let rest = text.dropFirst(keyword.count)
            if keyword == "title", rest.first?.isWhitespace == true {
                diagram.title = rest.trimmingWhitespace()
            } else if keyword == "section", rest.first?.isWhitespace == true, !rest.contains(":") {
                diagram.sections.append(rest.trimmingWhitespace())
            } else {
                diagram.tasks.append(try task(text, line: line, section: diagram.sections.isEmpty ? nil : diagram.sections.count - 1))
            }
        }
        return diagram
    }

    private static func task(_ text: String, line: SourceLine, section: Int?) throws -> JourneyDiagram.Task {
        let parts = text.split(separator: ":", omittingEmptySubsequences: false).map { $0.trimmingWhitespace() }
        guard parts.count >= 2, !parts[0].isEmpty else {
            throw MermaidError.syntax("Expected a task written as 'name: score: actors', found '\(text)'", at: line.location)
        }
        let scoreOffset = text.distance(from: text.startIndex, to: text.firstIndex(of: ":")!) + 1
        guard let score = Double(parts[1]), score.isFinite else {
            throw MermaidError.syntax("Task '\(parts[0])' needs a numeric score from 1 to 5, found '\(parts[1])'",
                                      at: line.location(atOffset: scoreOffset))
        }
        let actors = parts.count > 2
            ? parts[2].split(separator: ",").map { $0.trimmingWhitespace() }.filter { !$0.isEmpty } : []
        return JourneyDiagram.Task(name: parts[0], score: score, actors: actors, section: section)
    }
}
