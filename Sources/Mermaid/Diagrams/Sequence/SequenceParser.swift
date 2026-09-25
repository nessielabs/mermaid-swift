/// Parses sequence diagram source into a `SequenceDiagram`.
///
/// Statements are line- or `;`-separated. Keywords are case-insensitive,
/// as in mermaid.js, but only count as keywords when followed by
/// whitespace, so participants such as `endpoint` or `optimizer` work
/// where mermaid.js would misread them.
struct SequenceParser {
    typealias Statement = SequenceDiagram.Statement

    var diagram = SequenceDiagram()
    var participantIndex: [String: Int] = [:]

    struct OpenBlock {
        var block: SequenceDiagram.Block
        var location: SourceLocation
    }
    /// Blocks awaiting `end`, innermost last.
    var openBlocks: [OpenBlock] = []
    /// The `box` awaiting `end`, if any.
    var openBox: (index: Int, location: SourceLocation)?
    /// A `create` whose message has not been seen yet.
    var pendingCreate: (id: String, location: SourceLocation)?
    /// `destroy` statements whose message has not been seen yet.
    var pendingDestroys: [(id: String, location: SourceLocation)] = []
    /// Open activations per participant, to reject unbalanced `deactivate`s.
    var activationDepth: [String: Int] = [:]
    /// The `autonumber` state: whether numbers show, the next number, and the step.
    var numbering = (visible: false, next: 1.0, step: 1.0)

    static func parse(_ source: DiagramSource) throws -> SequenceDiagram {
        var parser = SequenceParser()
        parser.diagram.accessibility = source.accessibility
        for statement in SequenceStatementSplitter.split(source.lines) {
            try parser.statement(statement)
        }
        try parser.finish()
        return parser.diagram
    }

    mutating func finish() throws {
        if let open = openBlocks.last {
            throw MermaidError.syntax("'\(open.block.kind.rawValue)' block is missing 'end'", at: open.location)
        }
        if let box = openBox {
            throw MermaidError.syntax("'box' is missing 'end'", at: box.location)
        }
        if let create = pendingCreate {
            throw MermaidError.semantic("Created participant '\(create.id)' has no creating message after it", at: create.location)
        }
        if let destroy = pendingDestroys.first {
            throw MermaidError.semantic("Destroyed participant '\(destroy.id)' has no destroying message after it", at: destroy.location)
        }
    }

    // MARK: - Dispatch

    static let blockKeywords: [String: SequenceDiagram.BlockKind] = [
        "loop": .loop, "alt": .alt, "opt": .opt, "par": .par, "par_over": .parOver,
        "critical": .critical, "break": .break, "rect": .rect,
    ]

    mutating func statement(_ s: SequenceStatementText) throws {
        guard let (keyword, rest, restOffset) = Self.keyword(in: s.text), !isSignal(s.text, startingWith: keyword) else {
            guard openBox == nil else { throw Self.insideBoxError(s) }
            return try signal(s)
        }
        if openBox != nil, !["participant", "actor", "destroy", "end"].contains(keyword) {
            throw Self.insideBoxError(s)
        }
        switch keyword {
        case "participant", "actor":
            try declare(rest, kind: keyword == "actor" ? .actor : .participant, created: false, s, at: restOffset)
        case "create":
            guard let (kind, declaration, offset) = Self.keyword(in: rest), kind == "participant" || kind == "actor" else {
                throw MermaidError.syntax("Expected 'participant' or 'actor' after 'create'", at: s.location(at: restOffset))
            }
            try declare(declaration, kind: kind == "actor" ? .actor : .participant, created: true, s, at: restOffset + offset)
        case "destroy":
            let id = try participantName(rest, s, at: restOffset)
            ensureParticipant(id)
            pendingDestroys.append((id, s.location))
        case "box": try openBox(rest, s)
        case "end": try end(rest, s)
        case "else", "and", "option": try section(keyword, label: rest, s)
        case "note": try note(rest, s, at: restOffset)
        case "activate":
            let id = try participantName(rest, s, at: restOffset)
            ensureParticipant(id)
            activationDepth[id, default: 0] += 1
            append(.activate(id))
        case "deactivate":
            let id = try participantName(rest, s, at: restOffset)
            ensureParticipant(id)
            try deactivate(id, at: s.location)
            append(.deactivate(id))
        case "autonumber": try autonumber(rest, s, at: restOffset)
        case "title": diagram.title = rest.hasPrefix(":") ? String(rest.dropFirst()).trimmingWhitespace() : rest
        case "link", "links", "properties", "details": try menu(keyword, rest, s, at: restOffset)
        default:
            if let kind = Self.blockKeywords[keyword] {
                try openBlock(kind, rest, s)
            } else {
                try signal(s)
            }
        }
    }

    /// The leading keyword (lowercased), the text after it, and that
    /// text's offset. A keyword must be followed by whitespace, the end of
    /// the statement, or (for `title:`) a colon.
    static func keyword(in text: String) -> (String, String, Int)? {
        let word = text.prefix { $0.isLetter || $0 == "_" }
        guard !word.isEmpty else { return nil }
        let after = text.dropFirst(word.count)
        let lower = word.lowercased()
        guard after.isEmpty || after.first == " " || after.first == "\t" || (lower == "title" && after.first == ":") else {
            return nil
        }
        let gap = after.prefix { $0 == " " || $0 == "\t" }.count
        return (lower, String(after.dropFirst(gap)).trimmingWhitespace(), word.count + gap)
    }

    /// Whether a statement starting with a keyword is really a message
    /// from a participant named like the keyword, as in `Note ->> B: hi`.
    func isSignal(_ text: String, startingWith keyword: String) -> Bool {
        let head = text.splitOnce(":")?.0 ?? text
        guard let signal = SequenceArrowScanner.signal(in: head) else { return false }
        return signal.source.lowercased() == keyword
    }

    static func insideBoxError(_ s: SequenceStatementText) -> MermaidError {
        .syntax("Only participant declarations are allowed inside 'box'", at: s.location)
    }

    /// Appends a statement to the innermost open block section.
    mutating func append(_ statement: Statement) {
        guard !openBlocks.isEmpty else { return diagram.statements.append(statement) }
        let b = openBlocks.count - 1
        openBlocks[b].block.sections[openBlocks[b].block.sections.count - 1].statements.append(statement)
    }

    /// Splits a leading `wrap:` or `nowrap:` (optionally after a `:`) off text.
    static func extractWrap(_ text: String) -> (text: String, wrap: Bool?) {
        var body = text.trimmingWhitespace()
        if body.hasPrefix(":wrap:") || body.hasPrefix(":nowrap:") { body.removeFirst() }
        if body.hasPrefix("wrap:") { return (String(body.dropFirst(5)).trimmingWhitespace(), true) }
        if body.hasPrefix("nowrap:") { return (String(body.dropFirst(7)).trimmingWhitespace(), false) }
        return (body, nil)
    }
}
