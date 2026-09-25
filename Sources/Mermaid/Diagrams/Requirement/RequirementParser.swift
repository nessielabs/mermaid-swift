/// Parses `requirementDiagram` source into a `RequirementDiagram`.
///
/// The grammar is line oriented: requirement and element blocks
/// (`kind name {` ... `}` with one `field: value` per line),
/// relationships (`a - satisfies -> b` or `b <- satisfies - a`),
/// `direction`, and styling (`style`, `classDef`, `class`, `:::`).
/// Keywords are case-insensitive, as in mermaid.js.
struct RequirementParser {
    typealias Diagram = RequirementDiagram

    var lines: [SourceLine]
    var index = 0
    var diagram = Diagram()

    init(_ source: DiagramSource) throws {
        lines = source.lines
        diagram.accessibility = source.accessibility
        guard source.headerArguments.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(source.headerArguments)' after 'requirementDiagram'",
                                      at: source.header.location)
        }
    }

    static func parse(_ source: DiagramSource) throws -> RequirementDiagram {
        var parser = try RequirementParser(source)
        try parser.run()
        return parser.diagram
    }

    mutating func run() throws {
        while index < lines.count {
            let line = lines[index]
            index += 1
            try statement(line)
        }
    }

    mutating func statement(_ line: SourceLine) throws {
        let text = line.text.hasSuffix(";") ? String(line.text.dropLast()).trimmingWhitespace() : line.text
        let (keyword, rest) = Self.splitFirstWord(text)
        switch keyword.lowercased() {
        case "direction":
            guard let direction = LayeredGraph.Direction(keyword: rest), rest.count == 2 else {
                throw MermaidError.syntax("Unknown direction '\(rest)'", at: line.location)
            }
            diagram.direction = direction
        case "classdef":
            let (names, css) = Self.splitFirstWord(rest)
            guard !names.isEmpty else { throw MermaidError.syntax("classDef needs a class name", at: line.location) }
            for name in Self.list(names) {
                diagram.classDefinitions[name] = (diagram.classDefinitions[name] ?? ElementStyle())
                    .overlaid(with: ElementStyle(css: css))
            }
        case "class":
            let (ids, classes) = Self.splitFirstWord(rest)
            guard !classes.isEmpty else {
                throw MermaidError.syntax("class needs node names and class names", at: line.location)
            }
            for id in Self.list(ids) { applyClasses(Self.list(classes), to: id) }
        case "style":
            let (ids, css) = Self.splitFirstWord(rest)
            guard !ids.isEmpty else { throw MermaidError.syntax("style needs a node name", at: line.location) }
            for id in Self.list(ids) { applyStyle(ElementStyle(css: css), to: id) }
        default:
            if text.hasSuffix("{") {
                try block(line, keyword: keyword, rest: String(rest.dropLast()).trimmingWhitespace())
            } else if let relationship = try RequirementRelationshipScanner.scan(text, at: line.location) {
                diagram.relationships.append(relationship)
            } else if let (name, classes) = text.splitOnce(":::") {
                applyClasses(Self.list(classes), to: name.trimmingWhitespace().unquoted)
            } else {
                throw MermaidError.syntax("Expected a requirement, element, relationship, or style statement",
                                          at: line.location)
            }
        }
    }

    static func splitFirstWord(_ text: String) -> (String, String) {
        let word = String(text.prefix { !$0.isWhitespace })
        return (word, String(text.dropFirst(word.count)).trimmingWhitespace())
    }

    static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingWhitespace().unquoted }.filter { !$0.isEmpty }
    }

    mutating func applyClasses(_ classes: [String], to name: String) {
        if let i = diagram.requirements.firstIndex(where: { $0.name == name }) {
            diagram.requirements[i].classes += classes
        } else if let i = diagram.elements.firstIndex(where: { $0.name == name }) {
            diagram.elements[i].classes += classes
        }
    }

    mutating func applyStyle(_ style: ElementStyle, to name: String) {
        if let i = diagram.requirements.firstIndex(where: { $0.name == name }) {
            diagram.requirements[i].style = diagram.requirements[i].style.overlaid(with: style)
        } else if let i = diagram.elements.firstIndex(where: { $0.name == name }) {
            diagram.elements[i].style = diagram.elements[i].style.overlaid(with: style)
        }
    }
}
