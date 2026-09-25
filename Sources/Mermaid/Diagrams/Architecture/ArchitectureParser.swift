/// Parses architecture diagram source into an `ArchitectureDiagram`.
///
/// Statements are line-oriented:
/// ```
/// group api(cloud)[API]
/// service db(database)[Database] in api
/// junction j in api
/// db:L -[reads]- R:server{group}
/// align row a b c
/// ```
/// Identifiers must be declared before they are used, as in mermaid.js.
struct ArchitectureParser {
    var diagram = ArchitectureDiagram()
    /// Every declared id and whether it names a group.
    var declared: [String: Bool] = [:]

    static func parse(_ source: DiagramSource) throws -> ArchitectureDiagram {
        var parser = ArchitectureParser()
        parser.diagram.accessibility = source.accessibility
        for line in source.lines { try parser.statement(line) }
        return parser.diagram
    }

    mutating func statement(_ line: SourceLine) throws {
        var scanner = Scanner(line.text, at: line.location)
        if Self.keyword("title", &scanner) {
            diagram.title = scanner.read { _ in true }.trimmingWhitespace()
        } else if Self.keyword("group", &scanner) {
            try group(&scanner)
        } else if Self.keyword("service", &scanner) {
            try node(&scanner, kind: .service)
        } else if Self.keyword("junction", &scanner) {
            try node(&scanner, kind: .junction)
        } else if Self.keyword("align", &scanner) {
            try alignment(&scanner)
        } else {
            try edge(&scanner)
        }
        scanner.skipWhitespace()
        if let c = scanner.peek(), !scanner.hasPrefix("%%") {
            throw MermaidError.syntax("Unexpected '\(c)'", at: scanner.location)
        }
    }

    // MARK: - Declarations

    mutating func group(_ scanner: inout Scanner) throws {
        let (id, location) = try Self.identifier(&scanner, what: "a group id")
        let icon = try Self.icon(&scanner)
        let title = try Self.title(&scanner)
        let parent = try parentClause(&scanner, for: id, kind: "group")
        try register(id, isGroup: true, at: location)
        diagram.groups.append(.init(id: id, icon: icon, title: title, parent: parent))
    }

    mutating func node(_ scanner: inout Scanner, kind: ArchitectureDiagram.Node.Kind) throws {
        let (id, location) = try Self.identifier(&scanner, what: kind == .service ? "a service id" : "a junction id")
        var icon: String?, iconText: String?, title: String?
        if kind == .service {
            scanner.skipWhitespace()
            if scanner.peek() == "\"" || scanner.peek() == "'" {
                iconText = try Self.quoted(&scanner)
            } else {
                icon = try Self.icon(&scanner)
            }
            title = try Self.title(&scanner)
        }
        let parent = try parentClause(&scanner, for: id, kind: kind == .service ? "service" : "junction")
        try register(id, isGroup: false, at: location)
        diagram.nodes.append(.init(id: id, kind: kind, icon: icon, iconText: iconText, title: title, parent: parent))
    }

    /// `in parentId`, validated like mermaid.js: the parent must be an
    /// already declared group other than the declaration itself.
    mutating func parentClause(_ scanner: inout Scanner, for id: String, kind: String) throws -> String? {
        scanner.skipWhitespace()
        guard scanner.consumeKeyword("in", caseInsensitive: false) else { return nil }
        let (parent, location) = try Self.identifier(&scanner, what: "a parent group id")
        if parent == id { throw MermaidError.semantic("The \(kind) [\(id)] cannot be placed within itself", at: location) }
        guard let isGroup = declared[parent] else {
            throw MermaidError.semantic("The \(kind) [\(id)]'s parent [\(parent)] does not exist; declare it first", at: location)
        }
        guard isGroup else { throw MermaidError.semantic("The \(kind) [\(id)]'s parent is not a group", at: location) }
        return parent
    }

    mutating func register(_ id: String, isGroup: Bool, at location: SourceLocation) throws {
        guard declared[id] == nil else {
            throw MermaidError.semantic("The id [\(id)] is already in use by another \(declared[id]! ? "group" : "service or junction")", at: location)
        }
        declared[id] = isGroup
        diagram.declarationOrder.append(id)
    }

    mutating func alignment(_ scanner: inout Scanner) throws {
        scanner.skipWhitespace()
        let axisLocation = scanner.location
        let axisWord = scanner.read { $0.isWordCharacter }
        guard let axis = ArchitectureDiagram.Alignment.Axis(rawValue: axisWord) else {
            throw MermaidError.syntax("Expected 'row' or 'column' after 'align'", at: axisLocation)
        }
        var members: [String] = []
        while true {
            scanner.skipWhitespace()
            if scanner.isAtEnd || scanner.hasPrefix("%%") { break }
            let (id, location) = try Self.identifier(&scanner, what: "a service or junction id")
            guard declared[id] == false else {
                throw MermaidError.semantic("align \(axis.rawValue) member [\(id)] must be a declared service or junction", at: location)
            }
            guard !members.contains(id) else {
                throw MermaidError.semantic("align \(axis.rawValue) lists [\(id)] more than once", at: location)
            }
            members.append(id)
        }
        guard members.count >= 2 else {
            throw MermaidError.syntax("align \(axis.rawValue) needs at least two members", at: axisLocation)
        }
        diagram.alignments.append(.init(axis: axis, members: members))
    }

    // MARK: - Edges

    /// `lhs{group}?:SIDE <?(--|-[label]-)>? SIDE:rhs{group}?`
    mutating func edge(_ scanner: inout Scanner) throws {
        let (from, fromLocation) = try Self.identifier(&scanner, what: "a statement")
        let fromGroup = scanner.consume("{group}")
        try scanner.expect(":", "Expected ':' and a side (L, R, T, B) after '\(from)'")
        let fromSide = try Self.side(&scanner)
        scanner.skipWhitespace()
        let arrowAtSource = scanner.consume("<")
        var label: String?
        if scanner.consume("--") {
            // Plain connector.
        } else if scanner.peek() == "-", scanner.peek(1) == "[" {
            scanner.advance()
            label = try Self.title(&scanner)
            try scanner.expect("-", "Expected '-' to close the edge label")
        } else {
            throw MermaidError.syntax("Expected '--' or '-[label]-'", at: scanner.location)
        }
        let arrowAtTarget = scanner.consume(">")
        scanner.skipWhitespace()
        let toSide = try Self.side(&scanner)
        try scanner.expect(":", "Expected ':' after the side")
        let (to, toLocation) = try Self.identifier(&scanner, what: "a target id")
        let toGroup = scanner.consume("{group}")
        try validateEndpoint(from, usesGroup: fromGroup, at: fromLocation)
        try validateEndpoint(to, usesGroup: toGroup, at: toLocation)
        let fromParent = diagram.node(from)?.parent, toParent = diagram.node(to)?.parent
        if fromGroup || toGroup, let fromParent, fromParent == toParent {
            throw MermaidError.semantic("The {group} modifier cannot join [\(from)] and [\(to)], which share group [\(fromParent)]",
                                        at: fromGroup ? fromLocation : toLocation)
        }
        diagram.edges.append(.init(from: from, fromSide: fromSide, fromGroup: fromGroup, to: to, toSide: toSide,
                                   toGroup: toGroup, arrowAtSource: arrowAtSource, arrowAtTarget: arrowAtTarget,
                                   label: label))
    }

    func validateEndpoint(_ id: String, usesGroup: Bool, at location: SourceLocation) throws {
        switch declared[id] {
        case nil:
            throw MermaidError.semantic("Edge endpoint [\(id)] is not a declared service or junction", at: location)
        case true?:
            throw MermaidError.semantic("Edges cannot use group [\(id)] directly; use a member service with {group}", at: location)
        case false?:
            if usesGroup, diagram.node(id)?.parent == nil {
                throw MermaidError.semantic("[\(id)] is not in a group, so it cannot use the {group} modifier", at: location)
            }
        }
    }

    // MARK: - Tokens

    /// Consumes a statement keyword followed by whitespace (or the end, for
    /// `title`), so ids such as `group-a` still start edges.
    static func keyword(_ word: String, _ scanner: inout Scanner) -> Bool {
        guard scanner.hasPrefix(word) else { return false }
        if let next = scanner.peek(word.count), next != " ", next != "\t" { return false }
        scanner.advance(by: word.count)
        return true
    }

    /// An id: word characters and inner dashes (`[\w]([-\w]*\w)?`).
    static func identifier(_ scanner: inout Scanner, what: String) throws -> (String, SourceLocation) {
        scanner.skipWhitespace()
        let location = scanner.location
        var probe = scanner
        var id = "", committed = scanner, pendingDashes = ""
        while let c = probe.peek(), c.isWordCharacter || c == "-" {
            probe.advance()
            if c == "-" {
                pendingDashes.append(c)
            } else {
                id += pendingDashes + String(c)
                pendingDashes = ""
                committed = probe
            }
        }
        guard !id.isEmpty, id.first != "-" else {
            let found = scanner.peek().map { "'\($0)'" } ?? "end of line"
            throw MermaidError.syntax("Expected \(what) but found \(found)", at: location)
        }
        scanner = committed
        return (id, location)
    }

    static func side(_ scanner: inout Scanner) throws -> ArchitectureDiagram.Side {
        let location = scanner.location
        guard let c = scanner.peek(), let side = ArchitectureDiagram.Side(rawValue: String(c)) else {
            throw MermaidError.syntax("Expected a side: L, R, T, or B", at: location)
        }
        scanner.advance()
        return side
    }

    /// `(name)`, where names may contain `-` and `:` (`logos:aws-s3`).
    static func icon(_ scanner: inout Scanner) throws -> String? {
        guard scanner.peek() == "(" else { return nil }
        let location = scanner.location
        scanner.advance()
        let name = scanner.read { $0.isWordCharacter || $0 == "-" || $0 == ":" }
        guard !name.isEmpty, scanner.consume(")") else {
            throw MermaidError.syntax("Expected an icon name like (database) closed by ')'", at: location)
        }
        return name
    }

    /// `[Title]` or `["Quoted title"]`.
    static func title(_ scanner: inout Scanner) throws -> String? {
        guard scanner.peek() == "[" else { return nil }
        let location = scanner.location
        scanner.advance()
        if scanner.peek() == "\"" || scanner.peek() == "'" {
            let text = try quoted(&scanner)
            guard scanner.consume("]") else { throw MermaidError.syntax("Expected ']' after the title", at: scanner.location) }
            return text
        }
        guard let text = scanner.read(until: "]") else {
            throw MermaidError.syntax("Missing ']' to close the title", at: location)
        }
        scanner.advance()
        return text.trimmingWhitespace()
    }

    /// A single- or double-quoted string with backslash escapes.
    static func quoted(_ scanner: inout Scanner) throws -> String {
        let location = scanner.location
        guard let quote = scanner.advance() else { throw MermaidError.syntax("Expected a string", at: location) }
        var text = ""
        while let c = scanner.advance() {
            if c == quote { return text }
            if c == "\\", let next = scanner.advance() { text.append(next) } else { text.append(c) }
        }
        throw MermaidError.syntax("Unterminated string", at: location)
    }
}
