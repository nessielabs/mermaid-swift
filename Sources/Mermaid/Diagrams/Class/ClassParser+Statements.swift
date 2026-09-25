extension ClassParser {
    mutating func statement(_ s: inout Scanner) throws {
        if s.consume("}") {
            try closeNamespace(at: s.location)
            try continueLine(&s)
        } else if s.consumeKeyword("direction", caseInsensitive: false) {
            s.skipWhitespace()
            let location = s.location
            let word = s.read { !$0.isWhitespace }
            guard let direction = LayeredGraph.Direction(keyword: word) else {
                throw MermaidError.syntax("Unknown direction '\(word)'", at: location)
            }
            diagram.direction = direction
            try expectEnd(&s)
        } else if s.consumeKeyword("namespace", caseInsensitive: false) {
            try namespace(&s)
        } else if s.consumeKeyword("classDef", caseInsensitive: false) {
            try classDef(&s)
        } else if s.consumeKeyword("class", caseInsensitive: false) {
            try classStatement(&s)
        } else if s.consumeKeyword("cssClass", caseInsensitive: false) {
            try cssClass(&s)
        } else if s.consumeKeyword("style", caseInsensitive: false) {
            try style(&s)
        } else if s.consumeKeyword("click", caseInsensitive: false) {
            try click(&s)
        } else if s.consumeKeyword("link", caseInsensitive: false) {
            try link(&s)
        } else if s.consumeKeyword("callback", caseInsensitive: false) {
            try callback(&s)
        } else if s.consumeKeyword("note", caseInsensitive: false) {
            try note(&s)
        } else if let annotation = try ClassSyntax.annotation(&s) {
            // `<<interface>> Shape`
            s.skipWhitespace()
            let name = try ClassSyntax.requireClassName(&s)
            diagram.classes[ensureClass(name)].annotations.append(annotation)
            try expectEnd(&s)
        } else {
            try relationOrMember(&s)
        }
    }

    // MARK: - Class declarations

    /// `class Name~T~["Label"]:::style <<annotation>> { members }`, where
    /// the label, style, annotation and body are optional.
    mutating func classStatement(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let name = try ClassSyntax.requireClassName(&s)
        let i = ensureClass(name)
        if let namespace = namespaceStack.last { diagram.classes[i].namespace = namespace.id }
        while true {
            s.skipWhitespace()
            if s.peek() == "[" {
                diagram.classes[i].label = try bracketLabel(&s)
            } else if s.consume(":::") {
                let location = s.location
                let style = s.read { ClassSyntax.isNameCharacter($0) }
                guard !style.isEmpty else { throw MermaidError.syntax("Expected a style class name after ':::'", at: location) }
                diagram.classes[i].cssClasses.append(style)
            } else if let annotation = try ClassSyntax.annotation(&s) {
                diagram.classes[i].annotations.append(annotation)
            } else if s.peek() == "{" {
                openBody = OpenBlock(id: name.id, location: s.location)
                s.advance()
                try continueLine(&s)
                return
            } else {
                break
            }
        }
        try expectEnd(&s)
    }

    /// `["Label"]` after a class or namespace name.
    mutating func bracketLabel(_ s: inout Scanner) throws -> String {
        let start = s.location
        s.advance()
        s.skipWhitespace()
        let label = try ClassSyntax.requireString(&s, "a label")
        s.skipWhitespace()
        guard s.consume("]") else { throw MermaidError.syntax("Expected ']' to close the label", at: start) }
        return label
    }

    // MARK: - Relations and member lines

    /// `A : member`, a bare `A`, or a relation
    /// `A "1" <|-- "many" B : label`.
    mutating func relationOrMember(_ s: inout Scanner) throws {
        let first = try ClassSyntax.requireClassName(&s, "a statement")
        s.skipWhitespace()
        if s.isAtEnd {
            // mermaid.js ignores a bare class name; declaring the class is
            // the more useful reading and loses nothing.
            ensureClass(first)
            return
        }
        if s.peek() == ":", !s.hasPrefix(":::") {
            s.advance()
            ensureClass(first)
            addMember(s.read { $0 != "\n" }, to: first.id)
            return
        }
        let fromCardinality = try ClassSyntax.string(&s)
        s.skipWhitespace()
        let operatorLocation = s.location
        guard let op = ClassSyntax.relationOperator(&s) else {
            let found = s.peek().map { "'\($0)'" } ?? "end of line"
            throw MermaidError.syntax("Expected a relation such as '-->' or a ':' member but found \(found)",
                                      at: operatorLocation)
        }
        s.skipWhitespace()
        let toCardinality = try ClassSyntax.string(&s)
        s.skipWhitespace()
        let second = try ClassSyntax.requireClassName(&s, "a class name after the relation")
        s.skipWhitespace()
        var label: String?
        if s.consume(":") {
            let text = s.read { $0 != "\n" }.trimmingWhitespace()
            label = text.isEmpty ? nil : text
        }
        try expectEnd(&s)
        addRelation(ClassDiagram.Relation(
            from: first.id, to: second.id, fromEnd: op.left, toEnd: op.right, line: op.line,
            fromCardinality: fromCardinality, toCardinality: toCardinality, label: label),
                    names: (first, second))
    }

    /// Records a relation. As in mermaid.js, a lollipop end facing an
    /// undecorated end turns its operand into a new interface node rather
    /// than a class; any other combination relates two classes.
    mutating func addRelation(_ relation: ClassDiagram.Relation,
                              names: (ClassSyntax.ClassName, ClassSyntax.ClassName)) {
        var relation = relation
        if relation.fromEnd == .lollipop, relation.toEnd == .none {
            ensureClass(names.1)
            relation.from = addInterface(label: names.0.id, classID: names.1.id)
        } else if relation.toEnd == .lollipop, relation.fromEnd == .none {
            ensureClass(names.0)
            relation.to = addInterface(label: names.1.id, classID: names.0.id)
        } else {
            ensureClass(names.0)
            ensureClass(names.1)
        }
        diagram.relations.append(relation)
    }

    mutating func addInterface(label: String, classID: String) -> String {
        let id = "interface\(diagram.interfaces.count)"
        diagram.interfaces.append(.init(id: id, label: label, classID: classID))
        return id
    }
}
