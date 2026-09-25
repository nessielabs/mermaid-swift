extension StateParser {
    /// Parses one statement piece. `nested` is true inside a composite body,
    /// the only place a `--` region separator is allowed.
    static func statement(_ piece: StatementPiece, nested: Bool) throws -> Parsed {
        let text = piece.text
        if text.count >= 2, text.allSatisfy({ $0 == "-" }) {
            guard nested else {
                throw MermaidError.syntax("The concurrency separator '--' is only allowed inside a composite state",
                                          at: piece.location)
            }
            return .statement(.divider(piece.location))
        }
        if let rest = keywordArgument("state", in: piece) { return try state(rest) }
        if let rest = keywordArgument("note", in: piece) { return try note(rest) }
        if let rest = keywordArgument("direction", in: piece) {
            guard let direction = LayeredGraph.Direction(keyword: rest.text) else {
                throw MermaidError.syntax("Unknown direction '\(rest.text)'", at: rest.location)
            }
            return .statement(.direction(direction))
        }
        if let rest = keywordArgument("classDef", in: piece) {
            let (names, css) = splitFirstWord(rest.text)
            return .statement(.classDef(names: list(names), style: ElementStyle(css: css)))
        }
        if let rest = keywordArgument("class", in: piece) { return try applyClass(rest) }
        if let rest = keywordArgument("style", in: piece) {
            let (ids, css) = splitFirstWord(rest.text)
            return .statement(.style(ids: list(ids), style: ElementStyle(css: css), location: rest.location))
        }
        if let rest = keywordArgument("click", in: piece) { return .statement(click(rest)) }
        if let rest = keywordArgument("hide", in: piece) {
            guard rest.text.lowercased().split(separator: " ") == ["empty", "description"] else {
                throw MermaidError.syntax("Expected 'hide empty description'", at: rest.location)
            }
            return .statement(.hideEmptyDescription)
        }
        if let rest = keywordArgument("scale", in: piece) {
            let words = rest.text.split(separator: " ")
            guard let width = words.first.flatMap({ Double($0) }), words.count <= 2,
                  words.count == 1 || words[1].lowercased() == "width" else {
                throw MermaidError.syntax("Expected 'scale <number> width'", at: rest.location)
            }
            return .statement(.scale(width))
        }
        return .statement(try transitionOrState(piece))
    }

    /// The text after a leading keyword (matched case-insensitively, as
    /// mermaid.js does) when the piece is that kind of statement. A keyword
    /// used as a state id (`note --> done`, `class : text`) does not count.
    static func keywordArgument(_ keyword: String, in piece: StatementPiece) -> StatementPiece? {
        let text = piece.text
        guard text.count > keyword.count, text.lowercased().hasPrefix(keyword.lowercased()),
              let next = text.dropFirst(keyword.count).first, next == " " || next == "\t" else { return nil }
        let afterKeyword = text.dropFirst(keyword.count)
        let spaces = afterKeyword.prefix { $0 == " " || $0 == "\t" }.count
        let rest = String(afterKeyword.dropFirst(spaces))
        guard !rest.hasPrefix("-->"), !rest.hasPrefix(":") else { return nil }
        let location = SourceLocation(line: piece.location.line, column: piece.location.column + keyword.count + spaces)
        return StatementPiece(text: rest, location: location)
    }

    // MARK: - Transitions and descriptions

    /// `a --> b : label`, `a : description`, or a bare `a`.
    static func transitionOrState(_ piece: StatementPiece) throws -> StateStatement {
        var s = Scanner(piece.text, at: piece.location)
        let first = try expectReference(&s)
        s.skipWhitespace()
        if s.consume("-->") {
            s.skipWhitespace()
            let second = try expectReference(&s)
            s.skipWhitespace()
            let label = try trailingText(&s)
            return .relation(from: first, to: second, label: label)
        }
        let description = try trailingText(&s)
        return .state(StateDeclaration(reference: first, descriptions: description.map { [$0] } ?? []))
    }

    /// An optional `: text` ending a statement; anything else is an error.
    static func trailingText(_ s: inout Scanner) throws -> String? {
        if s.consume(":") {
            let text = s.read { _ in true }.trimmingWhitespace()
            return text.isEmpty ? nil : text
        }
        if s.isAtEnd || s.peek() == "#" { return nil }
        throw MermaidError.syntax("Unexpected '\(s.peek()!)'", at: s.location)
    }

    static func expectReference(_ s: inout Scanner) throws -> StateReference {
        let location = s.location
        guard let reference = try reference(&s) else {
            let found = s.peek().map { "'\($0)'" } ?? "end of statement"
            throw MermaidError.syntax("Expected a state but found \(found)", at: location)
        }
        return reference
    }

    /// `[*]` or a state id, followed by any `:::class` shorthands.
    static func reference(_ s: inout Scanner) throws -> StateReference? {
        let location = s.location
        let id = s.consume("[*]") ? "[*]" : readID(&s)
        guard !id.isEmpty else { return nil }
        var reference = StateReference(id: id, location: location)
        while s.consume(":::") {
            let name = s.read { $0.isWordCharacter || $0 == "-" }
            guard !name.isEmpty else { throw MermaidError.syntax("Expected a class name after ':::'", at: s.location) }
            reference.classes.append(name)
        }
        return reference
    }

    /// A state id: anything up to whitespace, `:`, a brace, or a `--` arrow.
    /// Leniency beyond mermaid.js: single hyphens between other id
    /// characters (`state-1`) are part of the id.
    static func readID(_ s: inout Scanner) -> String {
        var id = ""
        while let c = s.peek() {
            if " \t:{}\";".contains(c) { break }
            if c == "-" {
                guard !id.isEmpty, let next = s.peek(1), !" \t-><:".contains(next) else { break }
            }
            id.append(c)
            s.advance()
        }
        return id
    }

    // MARK: - state

    static let specialKinds: [(String, StateDiagram.Kind)] = [
        ("<<fork>>", .fork), ("<<join>>", .join), ("<<choice>>", .choice),
        ("[[fork]]", .fork), ("[[join]]", .join), ("[[choice]]", .choice),
    ]

    /// `state "Description" as id`, `state id <<choice>>`, `state id`, with
    /// an optional trailing `{` opening a composite body.
    static func state(_ rest: StatementPiece) throws -> Parsed {
        var s = Scanner(rest.text, at: rest.location)
        if s.peek() == "\"" {
            let quoteLocation = s.location
            s.advance()
            guard let description = s.read(until: "\"") else {
                throw MermaidError.syntax("State description is missing its closing '\"'", at: quoteLocation)
            }
            s.advance()
            s.skipWhitespace()
            guard s.consumeKeyword("as") else {
                throw MermaidError.syntax("Expected 'as' after the state description", at: s.location)
            }
            s.skipWhitespace()
            let idLocation = s.location
            var idText = s.read { $0 != "{" }.trimmingWhitespace()
            let opens = s.consume("{")
            var declaration = StateDeclaration(reference: StateReference(id: "", location: idLocation),
                                               descriptions: [description.trimmingWhitespace()], usesKeyword: true)
            // `state "A" as a : more` adds a second description, as in mermaid.js.
            if let (id, extra) = idText.splitOnce(":"), !id.hasSuffix(":"), !extra.hasPrefix(":") {
                idText = id.trimmingWhitespace()
                if !extra.trimmingWhitespace().isEmpty { declaration.descriptions.append(extra.trimmingWhitespace()) }
            }
            var idScanner = Scanner(idText, at: idLocation)
            guard let reference = try reference(&idScanner), idScanner.isAtEnd else {
                throw MermaidError.syntax(idText.isEmpty ? "Expected a state id after 'as'"
                                          : "State id '\(idText)' must be a single word", at: idLocation)
            }
            declaration.reference = reference
            try expectEnd(&s)
            return opens ? .open(declaration) : .statement(.state(declaration))
        }
        let lower = rest.text.lowercased()
        if let (suffix, kind) = specialKinds.first(where: { lower.hasSuffix($0.0) }) {
            let id = String(rest.text.dropLast(suffix.count)).trimmingWhitespace()
            guard !id.isEmpty, !id.contains(where: { $0 == " " || $0 == "\t" }) else {
                throw MermaidError.syntax("Expected a single-word state id before '\(suffix)'", at: rest.location)
            }
            return .statement(.state(StateDeclaration(reference: StateReference(id: id, location: rest.location),
                                                      kind: kind, usesKeyword: true)))
        }
        let reference = try expectReference(&s)
        var declaration = StateDeclaration(reference: reference, usesKeyword: true)
        s.skipWhitespace()
        if s.consume("{") {
            try expectEnd(&s)
            return .open(declaration)
        }
        // Leniency beyond mermaid.js: `state id : description`.
        if s.consume(":") {
            let text = s.read { _ in true }.trimmingWhitespace()
            if !text.isEmpty { declaration.descriptions.append(text) }
            return .statement(.state(declaration))
        }
        if !s.isAtEnd, s.peek() != "#" {
            let message = rest.text.contains("{")
                ? "State name must be a single word, found '\(rest.text.prefix { $0 != "{" }.trimmingWhitespace())'"
                : "Unexpected '\(s.peek()!)'"
            throw MermaidError.syntax(message, at: s.location)
        }
        return .statement(.state(declaration))
    }

    static func expectEnd(_ s: inout Scanner) throws {
        s.skipWhitespace()
        if !s.isAtEnd { throw MermaidError.syntax("Unexpected '\(s.peek()!)'", at: s.location) }
    }

    // MARK: - note

    /// `note left of id : text`, `note right of id` (text on following
    /// lines), or a floating `note "text" as id`.
    static func note(_ rest: StatementPiece) throws -> Parsed {
        var s = Scanner(rest.text, at: rest.location)
        if s.peek() == "\"" {
            let location = s.location
            s.advance()
            guard let text = s.read(until: "\"") else {
                throw MermaidError.syntax("Note text is missing its closing '\"'", at: location)
            }
            s.advance()
            s.skipWhitespace()
            guard s.consumeKeyword("as") else { throw MermaidError.syntax("Expected 'as' after the note text", at: s.location) }
            s.skipWhitespace()
            let alias = readID(&s)
            guard !alias.isEmpty else { throw MermaidError.syntax("Expected a note id after 'as'", at: s.location) }
            try expectEnd(&s)
            return .statement(.note(target: nil, position: .floating, text: text.trimmingWhitespace(), alias: alias))
        }
        let position: StateDiagram.Note.Position
        if s.consumeKeyword("left") {
            position = .left
        } else if s.consumeKeyword("right") {
            position = .right
        } else {
            throw MermaidError.syntax("Expected 'left of', 'right of' or a quoted text after 'note'", at: s.location)
        }
        s.skipWhitespace()
        guard s.consumeKeyword("of") else { throw MermaidError.syntax("Expected 'of'", at: s.location) }
        s.skipWhitespace()
        let target = try expectReference(&s)
        s.skipWhitespace()
        if s.isAtEnd { return .noteBody(target: target, position: position, location: rest.location) }
        guard s.consume(":") else { throw MermaidError.syntax("Unexpected '\(s.peek()!)'", at: s.location) }
        let text = s.read { _ in true }.trimmingWhitespace()
        return .statement(.note(target: target, position: position, text: text, alias: nil))
    }

    // MARK: - class, click

    /// `class a, b name`: ids separated by commas (spaces allowed after
    /// them), then one or more class names.
    static func applyClass(_ rest: StatementPiece) throws -> Parsed {
        var s = Scanner(rest.text, at: rest.location)
        var ids: [String] = []
        repeat {
            s.skipWhitespace()
            let id = s.read { !" \t,".contains($0) }
            if !id.isEmpty { ids.append(id) }
            s.skipWhitespace()
        } while s.consume(",")
        let classes = list(s.read { _ in true })
        guard !ids.isEmpty, !classes.isEmpty else {
            throw MermaidError.syntax("Expected 'class <ids> <className>'", at: rest.location)
        }
        return .statement(.applyClass(ids: ids, classes: classes, location: rest.location))
    }

    /// `click id "url" "tooltip"` or `click id href "url"`.
    static func click(_ rest: StatementPiece) -> StateStatement {
        let (id, arguments) = splitFirstWord(rest.text)
        let quoted = arguments.split(separator: "\"", omittingEmptySubsequences: false).enumerated()
            .filter { $0.offset % 2 == 1 }.map { String($0.element) }
        return .click(id: id, url: quoted.first, tooltip: quoted.count > 1 ? quoted[1] : nil, location: rest.location)
    }

    // MARK: - Helpers

    static func splitFirstWord(_ text: String) -> (String, String) {
        let word = String(text.prefix { $0 != " " && $0 != "\t" })
        return (word, String(text.dropFirst(word.count)).trimmingWhitespace())
    }

    /// Splits on commas and whitespace, dropping empty entries.
    static func list(_ text: String) -> [String] {
        text.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "\t" }).map(String.init)
    }
}
