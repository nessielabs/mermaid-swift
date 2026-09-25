import Foundation

extension SequenceParser {
    /// `participant A`, `actor B as Bob`, `participant C@{ "type": "queue" } as Jobs`.
    mutating func declare(_ text: String, kind: SequenceDiagram.ParticipantKind, created: Bool,
                          _ s: SequenceStatementText, at offset: Int) throws {
        var idPart = text
        var alias: String?
        var kind = kind
        if let open = text.range(of: "@{") {
            idPart = String(text[..<open.lowerBound])
            guard let close = text[open.upperBound...].firstIndex(of: "}") else {
                throw MermaidError.syntax("Participant configuration is missing '}'", at: s.location(at: offset))
            }
            let configOffset = offset + text.distance(from: text.startIndex, to: open.lowerBound) + 1
            let config = try LenientJSON.parse(String(text[text.index(after: open.lowerBound)...close]),
                                               at: s.location(at: configOffset))
            if let type = config["type"]?.stringValue {
                guard let parsed = SequenceDiagram.ParticipantKind(rawValue: type.lowercased()) else {
                    throw MermaidError.syntax("Unknown participant type '\(type)'", at: s.location(at: configOffset))
                }
                kind = parsed
            }
            alias = config["alias"]?.stringValue
            let after = text[text.index(after: close)...].trimmingWhitespace()
            if !after.isEmpty {
                guard let (word, rest, _) = Self.keyword(in: after), word == "as" else {
                    throw MermaidError.syntax("Unexpected '\(after)' after participant configuration", at: s.location(at: offset))
                }
                alias = rest
            }
        } else if let separator = text.range(of: #"\s+as(\s+|$)"#, options: [.regularExpression, .caseInsensitive]) {
            idPart = String(text[..<separator.lowerBound])
            alias = String(text[separator.upperBound...])
        }
        let id = try participantName(idPart, s, at: offset)
        // Lenient: mermaid.js shows quotes around a quoted alias literally.
        let label = alias.map { Self.extractWrap($0) }.map { (text: $0.text.unquoted, wrap: $0.wrap) }
        let hasLabel = !(label?.text.isEmpty ?? true)
        try addParticipant(id, label: hasLabel ? label?.text : nil, wrap: label?.wrap,
                           kind: kind, explicit: hasLabel || text.contains("@{"), created: created, at: s.location)
    }

    /// Validates and unquotes a participant name.
    func participantName(_ text: String, _ s: SequenceStatementText, at offset: Int) throws -> String {
        let name = text.trimmingWhitespace().unquoted.trimmingWhitespace()
        guard !name.isEmpty else {
            throw MermaidError.syntax("Expected a participant name", at: s.location(at: offset))
        }
        if let bad = name.first(where: { "<>:,@".contains($0) }) {
            throw MermaidError.syntax("Participant names cannot contain '\(bad)'", at: s.location(at: offset))
        }
        return name
    }

    /// Declares a participant, following mermaid.js: redeclaring one
    /// without an alias or configuration only assigns its box, and a
    /// participant may belong to one box only.
    mutating func addParticipant(_ id: String, label: String?, wrap: Bool?, kind: SequenceDiagram.ParticipantKind,
                                 explicit: Bool, created: Bool, at location: SourceLocation) throws {
        if let i = participantIndex[id] {
            if created {
                throw MermaidError.semantic("Participant '\(id)' already exists and cannot be created again; use an alias instead", at: location)
            }
            if let box = openBox {
                if let current = diagram.participants[i].box, current != box.index {
                    throw MermaidError.semantic("Participant '\(id)' cannot belong to two boxes", at: location)
                }
                if diagram.participants[i].box == nil {
                    diagram.participants[i].box = box.index
                    diagram.boxes[box.index].participants.append(id)
                }
            }
            guard explicit else { return }
            diagram.participants[i].label = label ?? id
            diagram.participants[i].wrap = wrap
            diagram.participants[i].kind = kind
            return
        }
        var participant = SequenceDiagram.Participant(id: id, label: label, kind: kind)
        participant.wrap = wrap
        participant.isCreated = created
        if let box = openBox {
            participant.box = box.index
            diagram.boxes[box.index].participants.append(id)
        }
        participantIndex[id] = diagram.participants.count
        diagram.participants.append(participant)
        if created { pendingCreate = (id, location) }
    }

    /// Creates a participant on first reference.
    mutating func ensureParticipant(_ id: String) {
        guard participantIndex[id] == nil else { return }
        participantIndex[id] = diagram.participants.count
        diagram.participants.append(SequenceDiagram.Participant(id: id))
    }

    /// `box [color] [title]`: the color comes first, and a first word that
    /// is not a color starts the title. Hex colors are accepted too
    /// (mermaid.js reads `#` as a comment there).
    mutating func openBox(_ text: String, _ s: SequenceStatementText) throws {
        if let box = openBox {
            throw MermaidError.syntax("Boxes cannot be nested", at: box.location)
        }
        var color: Color?
        var title = text
        let lower = text.lowercased()
        if ["rgb", "rgba", "hsl", "hsla"].contains(where: { lower.hasPrefix($0 + "(") || lower.hasPrefix($0 + " (") }),
           let close = text.firstIndex(of: ")") {
            color = Color(css: String(text[...close]))
            title = String(text[text.index(after: close)...])
        } else {
            let word = String(text.prefix { !$0.isWhitespace })
            if !word.isEmpty, let parsed = Color(css: word) {
                color = parsed
                title = String(text.dropFirst(word.count))
            }
        }
        let (body, wrap) = Self.extractWrap(title)
        let box = SequenceDiagram.Box(title: body.isEmpty ? nil : body, color: color?.isClear == true ? nil : color, wrap: wrap)
        diagram.boxes.append(box)
        openBox = (diagram.boxes.count - 1, s.location)
    }

    /// `link A: Dashboard @ https://...`, `links A: {"Wiki": "https://..."}`.
    /// Menus are interactive in mermaid.js; they are kept on the model but
    /// not drawn. Malformed menus are ignored as mermaid.js does.
    mutating func menu(_ keyword: String, _ text: String, _ s: SequenceStatementText, at offset: Int) throws {
        guard let (name, value) = text.splitOnce(":") else {
            throw MermaidError.syntax("Expected ':' after the participant name", at: s.location(at: offset))
        }
        let id = try participantName(name, s, at: offset)
        ensureParticipant(id)
        guard let i = participantIndex[id] else { return }
        let body = LabelParser.decodeMermaidEntities(value.trimmingWhitespace())
        switch keyword {
        case "link":
            if let (label, url) = body.splitOnce("@") {
                diagram.participants[i].links.append(.init(name: label.trimmingWhitespace(), url: url.trimmingWhitespace()))
            }
        case "links":
            for (label, url) in ((try? LenientJSON.parse(body))?.objectValue ?? [:]).sorted(by: { $0.key < $1.key }) {
                if let url = url.stringValue { diagram.participants[i].links.append(.init(name: label, url: url)) }
            }
        default:
            break
        }
    }
}
