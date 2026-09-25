extension EntityRelationshipParser {
    /// `NAME`, `NAME[alias]`, `NAME:::class`, `NAME { attributes }`, or a
    /// relationship `A ||--o{ B : label`, in any valid combination.
    mutating func entityStatement() throws {
        let location = scanner.location
        guard let name = try entityName() else {
            let found = scanner.peek().map { "'\($0)'" } ?? "end of input"
            throw MermaidError.syntax("Expected an entity name but found \(found)", at: location)
        }
        let i = ensureEntity(name)
        scanner.skipWhitespace()
        if scanner.peek() == "[" {
            let aliasLocation = scanner.location
            scanner.advance()
            guard let alias = scanner.read(until: "]"), !alias.contains("\n") else {
                throw MermaidError.syntax("Entity alias is missing its closing ']'", at: aliasLocation)
            }
            scanner.advance()
            let text = alias.trimmingWhitespace().unquoted
            if !text.isEmpty, diagram.entities[i].alias == nil { diagram.entities[i].alias = text }
            definedEntities.insert(name)
            scanner.skipWhitespace()
        }
        applyClasses(classShorthand(), to: name)
        scanner.skipWhitespace()
        if scanner.peek() == "{" {
            let blockLocation = scanner.location
            scanner.advance()
            diagram.entities[i].attributes += try attributeBlock(of: name, at: blockLocation)
            definedEntities.insert(name)
            return
        }
        guard let relation = try EntityRelationshipRelationScanner.scan(&scanner) else { return }
        scanner.skipWhitespace()
        let targetLocation = scanner.location
        guard let target = try entityName() else {
            throw MermaidError.syntax("Relationship is missing its second entity", at: targetLocation)
        }
        ensureEntity(target)
        applyClasses(classShorthand(), to: target)
        scanner.skipWhitespace()
        var label = ""
        if scanner.consume(":") {
            label = try relationshipLabel()
        }
        diagram.relationships.append(.init(from: name, to: target, fromCardinality: relation.fromCardinality,
                                           toCardinality: relation.toCardinality,
                                           identifying: relation.identifying, label: label))
    }

    /// A quoted name, or letters, digits, `_`, `*`, and non-ASCII
    /// characters, with `-` and `.` allowed between them (so `LINE-ITEM` is
    /// one name but `A--B` stops at `A`).
    mutating func entityName() throws -> String? {
        if scanner.peek() == "\"" {
            let location = scanner.location
            scanner.advance()
            guard let text = scanner.read(until: "\""), !text.contains("\n") else {
                throw MermaidError.syntax("Entity name is missing its closing '\"'", at: location)
            }
            scanner.advance()
            return text
        }
        func isNameCharacter(_ c: Character) -> Bool { c.isWordCharacter || c == "*" || !c.isASCII }
        var name = ""
        while let c = scanner.peek() {
            if isNameCharacter(c) {
                name.append(c)
                scanner.advance()
            } else if c == "-" || c == ".", !name.isEmpty, let next = scanner.peek(1), isNameCharacter(next) {
                name.append(c)
                scanner.advance()
            } else {
                break
            }
        }
        return name.isEmpty ? nil : name
    }

    /// Classes from a `:::a,b` suffix, if present.
    mutating func classShorthand() -> [String] {
        guard scanner.consume(":::") else { return [] }
        let names = scanner.read { $0.isWordCharacter || $0 == "-" || $0 == "," || !$0.isASCII }
        return list(names)
    }

    /// A quoted label, or (leniently) the rest of the line.
    mutating func relationshipLabel() throws -> String {
        scanner.skipWhitespace()
        if scanner.peek() == "\"" {
            let location = scanner.location
            scanner.advance()
            guard let text = scanner.read(until: "\"") else {
                throw MermaidError.syntax("Relationship label is missing its closing '\"'", at: location)
            }
            scanner.advance()
            return text
        }
        return restOfLine()
    }

    /// Reads attribute lines up to the closing `}`. Quoted comments may
    /// contain braces.
    mutating func attributeBlock(of entity: String, at location: SourceLocation) throws -> [Diagram.Attribute] {
        var attributes: [Diagram.Attribute] = []
        var line = ""
        var lineStart = scanner.location
        var inQuote = false
        func flush() throws {
            let text = line.trimmingWhitespace()
            if !text.isEmpty {
                let offset = line.prefix { $0 == " " || $0 == "\t" }.count
                let start = SourceLocation(line: lineStart.line, column: lineStart.column + offset)
                attributes += try EntityRelationshipAttributeParser.parse(line: text, at: start)
            }
            line = ""
        }
        while let c = scanner.peek() {
            if c == "}", !inQuote {
                scanner.advance()
                try flush()
                return attributes
            }
            if c == "\"" { inQuote.toggle() }
            if c == "\n" {
                try flush()
                inQuote = false
                scanner.advance()
                lineStart = scanner.location
                continue
            }
            line.append(c)
            scanner.advance()
        }
        throw MermaidError.syntax("Entity '\(entity)' is missing its closing '}'", at: location)
    }

    /// The index of the entity named `name`, creating it on first mention
    /// and recording the mention for subgraph membership.
    @discardableResult
    mutating func ensureEntity(_ name: String) -> Int {
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].references.append(name) }
        if let i = entityIndex[name] { return i }
        diagram.entities.append(.init(name: name))
        entityIndex[name] = diagram.entities.count - 1
        return diagram.entities.count - 1
    }

    mutating func applyClasses(_ classes: [String], to id: String) {
        guard !classes.isEmpty else { return }
        if let i = diagram.subgraphs.firstIndex(where: { $0.id == id }) {
            diagram.subgraphs[i].classes += classes
        } else if let i = entityIndex[id] {
            diagram.entities[i].classes += classes
        }
    }

    mutating func applyStyle(_ style: ElementStyle, to id: String) {
        if let i = diagram.subgraphs.firstIndex(where: { $0.id == id }) {
            diagram.subgraphs[i].style = diagram.subgraphs[i].style.overlaid(with: style)
        } else if let i = entityIndex[id] {
            diagram.entities[i].style = diagram.entities[i].style.overlaid(with: style)
        }
    }
}
