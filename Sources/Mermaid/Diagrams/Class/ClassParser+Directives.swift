extension ClassParser {
    // MARK: - Namespaces

    /// `namespace Name["Label"] {`. Names nest by dots (`A.B` lives in
    /// `A`) and by syntax (a block inside another block), creating any
    /// missing ancestors, as in mermaid.js.
    mutating func namespace(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let location = s.location
        let name = try ClassSyntax.requireClassName(&s, "a namespace name")
        s.skipWhitespace()
        var label: String?
        if s.peek() == "[" { label = try bracketLabel(&s) }
        s.skipWhitespace()
        guard s.consume("{") else {
            throw MermaidError.syntax("Expected '{' after namespace '\(name.id)'", at: s.location)
        }
        let id = addNamespace(name.id, label: label)
        namespaceStack.append(OpenBlock(id: id, location: location))
        try continueLine(&s)
    }

    mutating func addNamespace(_ name: String, label: String?) -> String {
        let qualified = namespaceStack.last.map { "\($0.id).\(name)" } ?? name
        if let i = diagram.namespaces.firstIndex(where: { $0.id == qualified }) {
            diagram.namespaces[i].isExplicit = true
            if let label { diagram.namespaces[i].label = label }
            return qualified
        }
        let parts = qualified.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        var parent: String?
        for depth in parts.indices {
            let id = parts[...depth].joined(separator: ".")
            let isLeaf = depth == parts.count - 1
            if let i = diagram.namespaces.firstIndex(where: { $0.id == id }) {
                if isLeaf { diagram.namespaces[i].isExplicit = true }
            } else {
                diagram.namespaces.append(.init(id: id, label: isLeaf ? label ?? parts[depth] : parts[depth],
                                                parent: parent, isExplicit: isLeaf))
            }
            parent = id
        }
        return qualified
    }

    mutating func closeNamespace(at location: SourceLocation) throws {
        guard namespaceStack.popLast() != nil else {
            throw MermaidError.syntax("'}' without an open namespace or class body",
                                      at: Self.location(location, advancedBy: -1))
        }
    }

    // MARK: - Notes

    /// `note "text"` or `note for Class "text"`.
    mutating func note(_ s: inout Scanner) throws {
        s.skipWhitespace()
        var target: String?
        if s.consumeKeyword("for", caseInsensitive: false) {
            s.skipWhitespace()
            target = try ClassSyntax.requireClassName(&s).id
            s.skipWhitespace()
        }
        let text = try ClassSyntax.requireString(&s, "the note text")
        try expectEnd(&s)
        diagram.notes.append(.init(id: "note\(diagram.notes.count)", text: text, target: target,
                                   namespace: namespaceStack.last?.id))
    }

    // MARK: - Styling

    /// `classDef name1,name2 css`
    mutating func classDef(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let location = s.location
        let names = s.read { !$0.isWhitespace }
        guard !names.isEmpty else { throw MermaidError.syntax("Expected a style class name", at: location) }
        let style = ElementStyle(css: s.read { $0 != "\n" })
        for name in names.split(separator: ",").map({ $0.trimmingWhitespace() }) where !name.isEmpty {
            diagram.classDefinitions[name] = (diagram.classDefinitions[name] ?? ElementStyle()).overlaid(with: style)
        }
    }

    /// `cssClass "id1,id2" styleClass`
    mutating func cssClass(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let ids = try ClassSyntax.requireString(&s, "class ids")
        s.skipWhitespace()
        let location = s.location
        let name = s.read { ClassSyntax.isNameCharacter($0) }
        guard !name.isEmpty else { throw MermaidError.syntax("Expected a style class name", at: location) }
        try expectEnd(&s)
        for id in Self.idList(ids) { deferred.append((id, { $0.cssClasses.append(name) })) }
    }

    /// `style id css`
    mutating func style(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let id = try ClassSyntax.requireClassName(&s).id
        let style = ElementStyle(css: s.read { $0 != "\n" })
        deferred.append((id, { $0.style = $0.style.overlaid(with: style) }))
    }

    static func idList(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
    }

    // MARK: - Interaction

    /// `click id href "url" ["tooltip"] [target]` or
    /// `click id call name(args) ["tooltip"]`. Actions are recorded but
    /// never run.
    mutating func click(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let id = try ClassSyntax.requireClassName(&s).id
        s.skipWhitespace()
        if s.consumeKeyword("href", caseInsensitive: false) {
            s.skipWhitespace()
            try linkArguments(&s, id: id)
        } else if s.consumeKeyword("call", caseInsensitive: false) {
            s.skipWhitespace()
            let location = s.location
            let name = s.read { $0 != "(" && !$0.isWhitespace }.trimmingWhitespace()
            guard !name.isEmpty else { throw MermaidError.syntax("Expected a callback name", at: location) }
            if s.consume("(") {
                guard s.read(until: ")") != nil else {
                    throw MermaidError.syntax("Expected ')' to close the callback arguments", at: s.location)
                }
                s.advance()
            }
            try callbackArguments(&s, id: id, name: name)
        } else {
            throw MermaidError.syntax("Expected 'href' or 'call' after the class name", at: s.location)
        }
    }

    /// `link id "url" ["tooltip"] [target]`
    mutating func link(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let id = try ClassSyntax.requireClassName(&s).id
        s.skipWhitespace()
        try linkArguments(&s, id: id)
    }

    /// `callback id "function" ["tooltip"]`
    mutating func callback(_ s: inout Scanner) throws {
        s.skipWhitespace()
        let id = try ClassSyntax.requireClassName(&s).id
        s.skipWhitespace()
        let name = try ClassSyntax.requireString(&s, "the callback name")
        try callbackArguments(&s, id: id, name: name)
    }

    private mutating func linkArguments(_ s: inout Scanner, id: String) throws {
        let url = try ClassSyntax.requireString(&s, "a URL")
        s.skipWhitespace()
        let tooltip = try ClassSyntax.string(&s)
        s.skipWhitespace()
        var target: String?
        if s.peek() == "_" {
            let location = s.location
            let word = s.read { !$0.isWhitespace }
            guard ["_self", "_blank", "_parent", "_top"].contains(word) else {
                throw MermaidError.syntax("Unknown link target '\(word)'", at: location)
            }
            target = word
        }
        try expectEnd(&s)
        deferred.append((id, {
            $0.link = url
            $0.linkTarget = target ?? "_blank"
            if let tooltip { $0.tooltip = tooltip }
        }))
    }

    private mutating func callbackArguments(_ s: inout Scanner, id: String, name: String) throws {
        s.skipWhitespace()
        let tooltip = try ClassSyntax.string(&s)
        try expectEnd(&s)
        deferred.append((id, {
            $0.callback = name
            if let tooltip { $0.tooltip = tooltip }
        }))
    }
}
