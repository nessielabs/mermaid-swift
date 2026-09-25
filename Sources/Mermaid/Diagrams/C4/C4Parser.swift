/// Parses C4 diagram source into a `C4Diagram`.
///
/// The body is a sequence of macro calls such as `Person(alias, "Label")`,
/// boundary macros followed by a `{ ... }` block, `title` lines, and the
/// style statements `UpdateElementStyle`, `UpdateRelStyle`, and
/// `UpdateLayoutConfig`.
struct C4Parser {
    var scanner: Scanner
    var diagram = C4Diagram()
    /// Aliases of the boundaries currently open, innermost last.
    var openBoundaries: [(alias: String, location: SourceLocation)] = []
    /// Where each relationship was declared, for reference errors.
    var relationshipLocations: [SourceLocation] = []

    static func parse(_ source: DiagramSource) throws -> C4Diagram {
        var parser = C4Parser(scanner: Scanner(source.text))
        let keyword = Mermaid.headerKeyword(source.header.text)
        guard let kind = C4Diagram.Kind.allCases.first(where: { $0.rawValue.lowercased() == keyword.lowercased() }) else {
            throw MermaidError.syntax("Unknown C4 diagram type '\(keyword)'", at: source.header.location)
        }
        parser.diagram.kind = kind
        parser.diagram.accessibility = source.accessibility
        return try parser.run()
    }

    mutating func run() throws -> C4Diagram {
        while true {
            skipSeparators()
            if scanner.isAtEnd { break }
            try statement()
        }
        if let open = openBoundaries.last {
            throw MermaidError.syntax("Boundary '\(open.alias)' is missing its closing '}'", at: open.location)
        }
        try validateReferences()
        return diagram
    }

    mutating func skipSeparators() {
        while let c = scanner.peek(), c.isWhitespace || c == ";" { scanner.advance() }
        if scanner.hasPrefix("%%") {
            _ = scanner.readLine()
            skipSeparators()
        }
    }

    mutating func statement() throws {
        let location = scanner.location
        if scanner.consume("}") {
            guard openBoundaries.popLast() != nil else {
                throw MermaidError.syntax("'}' without an open boundary", at: location)
            }
            return
        }
        let name = scanner.read { $0.isWordCharacter }
        guard !name.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(scanner.peek()!)'", at: location)
        }
        switch name {
        case "title":
            diagram.title = scanner.readLine().trimmingWhitespace()
            return
        case "direction":
            // Accepted by mermaid's grammar; the C4 grid has no direction.
            _ = scanner.readLine()
            return
        default: break
        }
        scanner.skipWhitespace()
        guard scanner.peek() == "(" else {
            throw MermaidError.syntax("Expected '(' after '\(name)'", at: scanner.location)
        }
        let arguments = try C4Arguments.scan(&scanner)
        if let macro = C4Macro(name: name) {
            try apply(macro, arguments, at: location)
        } else if !C4Macro.ignored.contains(name) {
            throw MermaidError.syntax("Unknown C4 statement '\(name)'", at: location)
        }
        try finishStatement(opensBlock: C4Macro(name: name)?.opensBoundary ?? false, name: name)
    }

    /// Consumes the end of a statement: a boundary macro must be followed by
    /// `{` on the same or a following line; any other statement must end
    /// its line.
    mutating func finishStatement(opensBlock: Bool, name: String) throws {
        scanner.skipWhitespace()
        if opensBlock {
            var probe = scanner
            probe.skipWhitespace(newlines: true)
            if probe.consume("{") {
                scanner = probe
            } else {
                // A boundary without a block is empty; close it again.
                openBoundaries.removeLast()
            }
            return
        }
        if let c = scanner.peek(), c != "\n", c != ";", c != "}", !scanner.hasPrefix("%%") {
            throw MermaidError.syntax("Unexpected '\(c)' after \(name)(...)", at: scanner.location)
        }
    }

    // MARK: - Macros

    mutating func apply(_ macro: C4Macro, _ arguments: C4Arguments, at location: SourceLocation) throws {
        let values = arguments.values(for: macro.signature)
        switch macro {
        case .element(let category, let form, let external):
            let alias = try required("alias", values, macro: macro, at: location)
            addElement(alias: alias, values: values, category: category, form: form, external: external)
        case .boundary(let fixedType), .deploymentNode(_, let fixedType):
            let alias = try required("alias", values, macro: macro, at: location)
            addBoundary(alias: alias, values: values, macro: macro, defaultType: fixedType)
            openBoundaries.append((alias, location))
        case .relationship(let kind, _):
            let from = try required("from", values, macro: macro, at: location)
            let to = try required("to", values, macro: macro, at: location)
            var rel = C4Diagram.Relationship(kind: kind, from: from, to: to, label: values["label"] ?? "")
            rel.technology = values["techn"] ?? ""
            rel.description = values["descr"] ?? ""
            rel.sprite = values["sprite"]
            rel.tags = Self.tags(values["tags"])
            rel.link = values["link"]
            rel.index = values["index"]
            diagram.relationships.append(rel)
            relationshipLocations.append(location)
        case .updateElementStyle:
            let name = try required("elementName", values, macro: macro, at: location)
            let style = Self.elementStyle(values)
            if let i = diagram.elements.firstIndex(where: { $0.alias == name }) {
                diagram.elements[i].style = diagram.elements[i].style.overlaid(with: style)
                if let techn = values["techn"] { diagram.elements[i].technology = techn }
            } else if let i = diagram.boundaries.firstIndex(where: { $0.alias == name }) {
                diagram.boundaries[i].style = diagram.boundaries[i].style.overlaid(with: style)
            }
        case .updateRelStyle:
            let from = try required("from", values, macro: macro, at: location)
            let to = try required("to", values, macro: macro, at: location)
            for i in diagram.relationships.indices where diagram.relationships[i].from == from && diagram.relationships[i].to == to {
                if let color = values["textColor"].flatMap(Color.init(css:)) { diagram.relationships[i].textColor = color }
                if let color = values["lineColor"].flatMap(Color.init(css:)) { diagram.relationships[i].lineColor = color }
                if let x = values["offsetX"].flatMap(Self.integer) { diagram.relationships[i].offsetX = x }
                if let y = values["offsetY"].flatMap(Self.integer) { diagram.relationships[i].offsetY = y }
            }
        case .updateLayoutConfig:
            if let n = values["c4ShapeInRow"].flatMap(Self.integer), n >= 1 { diagram.shapesPerRow = Int(n) }
            if let n = values["c4BoundaryInRow"].flatMap(Self.integer), n >= 1 { diagram.boundariesPerRow = Int(n) }
        case .addElementTag:
            let tag = try required("tagStereo", values, macro: macro, at: location)
            diagram.elementTags[tag] = (diagram.elementTags[tag] ?? .init()).overlaid(with: Self.elementStyle(values))
        case .addRelTag:
            let tag = try required("tagStereo", values, macro: macro, at: location)
            diagram.relationshipTags[tag] = C4Diagram.RelationshipTagStyle(
                textColor: values["textColor"].flatMap(Color.init(css:)),
                lineColor: values["lineColor"].flatMap(Color.init(css:)),
                lineStyle: values["lineStyle"])
        }
    }

    func required(_ key: String, _ values: [String: String], macro: C4Macro, at location: SourceLocation) throws -> String {
        guard let value = values[key], !value.isEmpty else {
            throw MermaidError.syntax("\(macro.displayName) needs a '\(key)' argument", at: location)
        }
        return value
    }

    /// Adds an element, or updates it when the alias was declared before
    /// (mermaid.js merges redeclarations the same way).
    mutating func addElement(alias: String, values: [String: String], category: C4Diagram.Element.Category,
                             form: C4Diagram.Element.Form, external: Bool) {
        var element = diagram.element(alias)
            ?? C4Diagram.Element(alias: alias, label: "", category: category, form: form, isExternal: external)
        element.label = values["label"] ?? ""
        element.category = category
        element.form = form
        element.isExternal = external
        if let techn = values["techn"] { element.technology = techn }
        if let descr = values["descr"] { element.description = descr }
        if let sprite = values["sprite"] { element.sprite = sprite }
        if let tags = values["tags"] { element.tags = Self.tags(tags) }
        if let link = values["link"] { element.link = link }
        element.boundary = openBoundaries.last?.alias
        if let i = diagram.elements.firstIndex(where: { $0.alias == alias }) {
            diagram.elements[i] = element
        } else {
            diagram.elements.append(element)
        }
    }

    mutating func addBoundary(alias: String, values: [String: String], macro: C4Macro, defaultType: String) {
        var kind = C4Diagram.Boundary.Kind.boundary
        if case .deploymentNode(let alignment, _) = macro { kind = .deploymentNode(alignment) }
        var boundary = diagram.boundary(alias) ?? C4Diagram.Boundary(alias: alias, label: "")
        boundary.label = values["label"] ?? ""
        boundary.kind = kind
        boundary.type = values["type"] ?? defaultType
        if let descr = values["descr"] { boundary.description = descr }
        if let sprite = values["sprite"] { boundary.sprite = sprite }
        if let tags = values["tags"] { boundary.tags = Self.tags(tags) }
        if let link = values["link"] { boundary.link = link }
        boundary.parent = openBoundaries.last?.alias
        if let i = diagram.boundaries.firstIndex(where: { $0.alias == alias }) {
            diagram.boundaries[i] = boundary
        } else {
            diagram.boundaries.append(boundary)
        }
    }

    /// Relationships may connect elements and boundaries; anything else is
    /// an error mermaid.js reports only when drawing.
    func validateReferences() throws {
        let known = Set(diagram.elements.map(\.alias)).union(diagram.boundaries.map(\.alias))
        for (rel, location) in zip(diagram.relationships, relationshipLocations) {
            for alias in [rel.from, rel.to] where !known.contains(alias) {
                throw MermaidError.semantic("Relationship refers to unknown element '\(alias)'", at: location)
            }
        }
    }

    static func elementStyle(_ values: [String: String]) -> C4Diagram.ElementStyle {
        var style = C4Diagram.ElementStyle()
        style.background = values["bgColor"].flatMap(Color.init(css:))
        style.font = values["fontColor"].flatMap(Color.init(css:))
        style.border = values["borderColor"].flatMap(Color.init(css:))
        style.shape = values["shape"]
        style.shadowing = values["shadowing"]
        style.legendText = values["legendText"]
        return style
    }

    static func tags(_ text: String?) -> [String] {
        (text ?? "").split(separator: "+").flatMap { $0.split(separator: ",") }
            .map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
    }

    /// Parses integers the way `parseInt` does, accepting a leading sign
    /// and ignoring trailing text such as `px`.
    static func integer(_ text: String) -> Double? {
        let trimmed = text.trimmingWhitespace()
        let sign = trimmed.first == "-" ? -1.0 : 1.0
        let digits = trimmed.drop { $0 == "-" || $0 == "+" }.prefix { $0.isNumber }
        return Double(digits).map { $0 * sign }
    }
}
