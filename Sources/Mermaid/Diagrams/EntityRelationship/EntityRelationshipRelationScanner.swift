/// The part of a relationship statement between the two entity names, such
/// as `||--o{` or `one or more optionally to zero or one`.
struct EntityRelationshipRelationToken: Equatable {
    var fromCardinality: EntityRelationshipDiagram.Cardinality
    var toCardinality: EntityRelationshipDiagram.Cardinality
    var identifying: Bool
}

/// Recognizes every cardinality and line form mermaid.js accepts.
///
/// mermaid.js lexes cardinality symbols independently of which side they
/// are written on, so `}o` and `o{` both mean "zero or more" wherever they
/// appear; this scanner does the same.
enum EntityRelationshipRelationScanner {
    typealias Cardinality = EntityRelationshipDiagram.Cardinality

    /// Symbol and word forms, longest alternatives first so that `one or
    /// more` wins over `one` and `1+` over `1`.
    static let cardinalities: [(text: String, cardinality: Cardinality)] = [
        ("|o", .zeroOrOne), ("o|", .zeroOrOne), ("||", .exactlyOne),
        ("}o", .zeroOrMore), ("o{", .zeroOrMore), ("}|", .oneOrMore), ("|{", .oneOrMore),
        ("one or zero", .zeroOrOne), ("zero or one", .zeroOrOne),
        ("one or more", .oneOrMore), ("one or many", .oneOrMore), ("many(1)", .oneOrMore), ("1+", .oneOrMore),
        ("zero or more", .zeroOrMore), ("zero or many", .zeroOrMore), ("many(0)", .zeroOrMore), ("0+", .zeroOrMore),
        ("many", .zeroOrMore), ("only one", .exactlyOne), ("one", .exactlyOne), ("1", .exactlyOne),
    ]

    /// Line forms: `--`/`to` identify, `..`/`.-`/`-.`/`optionally to` do not.
    static let lines: [(text: String, identifying: Bool)] = [
        ("--", true), ("..", false), (".-", false), ("-.", false), ("optionally to", false), ("to", true),
    ]

    /// Scans a full relationship specification, or returns nil (leaving the
    /// scanner untouched) when the text does not start with a cardinality.
    /// Throws when a cardinality starts a relationship that is incomplete.
    static func scan(_ scanner: inout Scanner) throws -> EntityRelationshipRelationToken? {
        var s = scanner
        s.skipWhitespace()
        guard let from = cardinality(&s, allowParent: true) else { return nil }
        s.skipWhitespace()
        let lineLocation = s.location
        guard let identifying = line(&s) else {
            throw MermaidError.syntax("Expected a relationship line ('--' or '..') after the cardinality", at: lineLocation)
        }
        s.skipWhitespace()
        let toLocation = s.location
        guard let to = cardinality(&s, allowParent: false) else {
            throw MermaidError.syntax("Expected a cardinality such as '||', 'o{' or 'zero or more'", at: toLocation)
        }
        scanner = s
        return EntityRelationshipRelationToken(fromCardinality: from, toCardinality: to, identifying: identifying)
    }

    /// A cardinality; `u` (a multi-dimensional parent) counts only directly
    /// before a line, as in mermaid.js.
    static func cardinality(_ s: inout Scanner, allowParent: Bool) -> Cardinality? {
        if allowParent, s.peek() == "u", let next = s.peek(1), next == "-" || next == "." || next == "|" {
            s.advance()
            return .mdParent
        }
        for (text, cardinality) in cardinalities where matches(text, &s) { return cardinality }
        return nil
    }

    static func line(_ s: inout Scanner) -> Bool? {
        for (text, identifying) in lines where matches(text, &s) { return identifying }
        return nil
    }

    /// Consumes `text` (ignoring case). Texts ending in a word character
    /// must not run into a following word, so `one` does not match `ones`.
    private static func matches(_ text: String, _ s: inout Scanner) -> Bool {
        guard s.hasPrefix(text, caseInsensitive: true) else { return false }
        if let last = text.last, last.isWordCharacter, let next = s.peek(text.count), next.isWordCharacter {
            return false
        }
        s.advance(by: text.count)
        return true
    }
}
