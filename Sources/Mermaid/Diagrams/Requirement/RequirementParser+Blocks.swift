extension RequirementParser {
    /// A `kind name {` or `element name {` block through its closing `}`.
    /// The name may be quoted and may carry `:::classes`.
    mutating func block(_ header: SourceLine, keyword: String, rest: String) throws {
        var name = rest, classes: [String] = []
        if let (base, suffix) = rest.splitOnce(":::") {
            name = base
            classes = Self.list(suffix)
        }
        name = name.trimmingWhitespace().unquoted
        guard !name.isEmpty else {
            throw MermaidError.syntax("'\(keyword)' needs a name before '{'", at: header.location)
        }
        let fields = try blockFields(header, name: name)
        if keyword.lowercased() == "element" {
            var element = Diagram.Element(name: name)
            for field in fields {
                switch field.key {
                case "type": element.type = field.value
                case "docref": element.docRef = field.value
                default:
                    throw MermaidError.syntax("Unknown element field '\(field.key)'; expected type or docref",
                                              at: field.location)
                }
            }
            element.classes = classes
            if !diagram.elements.contains(where: { $0.name == name }) { diagram.elements.append(element) }
            return
        }
        guard let kind = Diagram.Kind.allCases.first(where: { $0.keyword.lowercased() == keyword.lowercased() }) else {
            throw MermaidError.syntax("Unknown block '\(keyword)'; expected a requirement type or 'element'",
                                      at: header.location)
        }
        var requirement = Diagram.Requirement(name: name, kind: kind)
        for field in fields {
            switch field.key {
            case "id": requirement.id = field.value
            case "text": requirement.text = field.value
            case "risk":
                requirement.risk = try choice(field, from: Diagram.Risk.allCases)
            case "verifymethod":
                requirement.verifyMethod = try choice(field, from: Diagram.VerifyMethod.allCases)
            default:
                throw MermaidError.syntax(
                    "Unknown requirement field '\(field.key)'; expected id, text, risk, or verifymethod",
                    at: field.location)
            }
        }
        requirement.classes = classes
        // As in mermaid.js, the first declaration of a name wins.
        if !diagram.requirements.contains(where: { $0.name == name }) { diagram.requirements.append(requirement) }
    }

    struct Field {
        /// The lowercased field name.
        var key: String
        var value: String
        var location: SourceLocation
    }

    /// `key: value` lines up to the closing `}`.
    mutating func blockFields(_ header: SourceLine, name: String) throws -> [Field] {
        var fields: [Field] = []
        while index < lines.count {
            let line = lines[index]
            index += 1
            if line.text == "}" { return fields }
            guard let (key, value) = line.text.splitOnce(":") else {
                throw MermaidError.syntax("Expected 'field: value' or '}' in '\(name)'", at: line.location)
            }
            var text = value.trimmingWhitespace()
            if text.hasSuffix(";") { text = String(text.dropLast()).trimmingWhitespace() }
            fields.append(Field(key: key.trimmingWhitespace().lowercased(), value: text.unquoted,
                                location: line.location))
        }
        throw MermaidError.syntax("'\(name)' is missing its closing '}'", at: header.location)
    }

    /// Matches a field value against a fixed set of choices, ignoring case.
    func choice<T: RawRepresentable & CaseIterable>(_ field: Field, from choices: T.AllCases) throws -> T
        where T.RawValue == String {
        if let match = choices.first(where: { $0.rawValue.lowercased() == field.value.lowercased() }) { return match }
        let expected = choices.map { $0.rawValue.lowercased() }.joined(separator: ", ")
        throw MermaidError.syntax("Unknown \(field.key) '\(field.value)'; expected one of \(expected)",
                                  at: field.location)
    }
}
