/// Scans a relationship statement: `source - type -> target` or its
/// mirror `target <- type - source`. Names are quoted or run up to the
/// arrow (so they may contain spaces, as in mermaid.js).
enum RequirementRelationshipScanner {
    typealias Relationship = RequirementDiagram.Relationship

    /// The relationship on `line`, nil when the line has no arrow at all,
    /// or a located error when an arrow is malformed.
    static func scan(_ line: String, at location: SourceLocation) throws -> Relationship? {
        var s = Scanner(line, at: location)
        guard let first = try name(&s), !first.isEmpty else { return nil }
        s.skipWhitespace()
        let leftward: Bool
        if s.consume("<-") { leftward = true } else if s.consume("-") { leftward = false } else { return nil }
        s.skipWhitespace()
        let typeLocation = s.location
        let word = s.read { $0.isWordCharacter }
        guard let type = RequirementDiagram.RelationshipType.allCases.first(where: { $0.rawValue == word.lowercased() }) else {
            let expected = RequirementDiagram.RelationshipType.allCases.map(\.rawValue).joined(separator: ", ")
            throw MermaidError.syntax("Unknown relationship '\(word)'; expected one of \(expected)", at: typeLocation)
        }
        s.skipWhitespace()
        let arrowLocation = s.location
        guard leftward ? s.consume("-") && !s.hasPrefix(">") : s.consume("->") else {
            throw MermaidError.syntax(leftward ? "Expected '-' after the relationship type"
                                               : "Expected '->' after the relationship type", at: arrowLocation)
        }
        s.skipWhitespace()
        let secondLocation = s.location
        guard let second = try name(&s), !second.isEmpty else {
            throw MermaidError.syntax("Relationship is missing its second name", at: secondLocation)
        }
        s.skipWhitespace()
        if let c = s.peek() { throw MermaidError.syntax("Unexpected '\(c)'", at: s.location) }
        return leftward ? Relationship(source: second, target: first, type: type)
                        : Relationship(source: first, target: second, type: type)
    }

    /// A quoted name, or everything up to the next `-`, `<`, or `>`.
    private static func name(_ s: inout Scanner) throws -> String? {
        s.skipWhitespace()
        if s.peek() == "\"" {
            let location = s.location
            s.advance()
            guard let text = s.read(until: "\"") else {
                throw MermaidError.syntax("Name is missing its closing '\"'", at: location)
            }
            s.advance()
            return text
        }
        let text = s.read { $0 != "-" && $0 != "<" && $0 != ">" }
        return text.trimmingWhitespace()
    }
}
