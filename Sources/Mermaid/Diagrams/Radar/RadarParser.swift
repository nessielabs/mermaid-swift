/// Parses `radar-beta` (and `radar`) source.
///
/// ```
/// radar-beta
///   title Grades
///   axis m["Math"], s["Science"], e["English"]
///   curve a["Alice"]{85, 90, 80}, b["Bob"]{ e: 70, m: 75, s: 85 }
///   max 100
///   min 0, ticks 5, graticule polygon, showLegend true
/// ```
///
/// Curve entries may span lines, so this parser works on characters.
/// Entries are either all plain numbers (in axis order) or all
/// `axisId: value` pairs, which may come in any order and must cover
/// every axis. Deliberate leniency: negative numbers are accepted (the
/// langium grammar only has unsigned numbers).
struct RadarParser {
    var scanner: Scanner
    var diagram = RadarDiagram()
    /// Curves whose entries name axes, resolved once every axis is known.
    var pending: [(index: Int, entries: [(axis: String, value: Double, location: SourceLocation)], location: SourceLocation)] = []

    static func parse(_ source: DiagramSource) throws -> RadarDiagram {
        var parser = RadarParser(scanner: Scanner(source.text))
        parser.diagram.accessibility = source.accessibility
        // `radar-beta:` and `radar-beta :` are both valid headers; anything
        // else on the header line is parsed as statements.
        var header = source.headerArguments
        var offset = source.header.text.count - header.count
        if header.hasPrefix(":") { header = String(header.dropFirst()); offset += 1 }
        if !header.trimmingWhitespace().isEmpty {
            var headerParser = RadarParser(scanner: Scanner(header, at: source.header.location(atOffset: offset)))
            try headerParser.run()
            parser.diagram = headerParser.diagram
            parser.pending = headerParser.pending
            parser.diagram.accessibility = source.accessibility
        }
        try parser.run()
        try parser.resolveReferences()
        return parser.diagram
    }

    mutating func run() throws {
        while true {
            skipBlank()
            if scanner.isAtEnd { return }
            try statement()
        }
    }

    /// Skips whitespace, newlines and `%%` comments.
    mutating func skipBlank() {
        while true {
            scanner.skipWhitespace(newlines: true)
            guard scanner.hasPrefix("%%") else { return }
            _ = scanner.read { $0 != "\n" }
        }
    }

    /// Skips spaces and a trailing comment, then requires the end of the
    /// line (or text).
    mutating func endOfStatement() throws {
        scanner.skipWhitespace()
        if scanner.hasPrefix("%%") { _ = scanner.read { $0 != "\n" } }
        guard scanner.isAtEnd || scanner.peek() == "\n" else {
            throw MermaidError.syntax("Unexpected '\(scanner.peek()!)'", at: scanner.location)
        }
    }

    mutating func statement() throws {
        let location = scanner.location
        let word = scanner.read { $0.isWordCharacter || $0 == "-" }
        switch word {
        case "title":
            guard scanner.isAtEnd || scanner.peek() == " " || scanner.peek() == "\t" || scanner.peek() == "\n" else {
                throw MermaidError.syntax("Unexpected '\(scanner.peek()!)' after title", at: scanner.location)
            }
            diagram.title = scanner.read { $0 != "\n" }.strippingInlineComment()
        case "axis":
            repeat {
                scanner.skipWhitespace()
                let id = try identifier("an axis id")
                diagram.axes.append(.init(id: id, label: try label()))
                scanner.skipWhitespace()
            } while scanner.consume(",")
            try endOfStatement()
        case "curve":
            repeat {
                scanner.skipWhitespace()
                try curve()
                scanner.skipWhitespace()
            } while scanner.consume(",")
            try endOfStatement()
        case "showLegend", "ticks", "max", "min", "graticule":
            try option(word, at: location)
            scanner.skipWhitespace()
            while scanner.consume(",") {
                scanner.skipWhitespace()
                let optionLocation = scanner.location
                try option(scanner.read { $0.isWordCharacter }, at: optionLocation)
                scanner.skipWhitespace()
            }
            try endOfStatement()
        case "":
            throw MermaidError.syntax("Unexpected '\(scanner.peek() ?? " ")'", at: location)
        default:
            throw MermaidError.syntax("Unknown radar statement '\(word)'", at: location)
        }
    }

    mutating func option(_ name: String, at location: SourceLocation) throws {
        scanner.skipWhitespace()
        let valueLocation = scanner.location
        switch name {
        case "showLegend":
            let value = scanner.read { $0.isLetter }
            guard value == "true" || value == "false" else {
                throw MermaidError.syntax("showLegend takes true or false", at: valueLocation)
            }
            diagram.showLegend = value == "true"
        case "graticule":
            let value = scanner.read { $0.isLetter }
            guard let graticule = RadarDiagram.Graticule(rawValue: value) else {
                throw MermaidError.syntax("graticule takes circle or polygon", at: valueLocation)
            }
            diagram.graticule = graticule
        case "ticks":
            let value = try number()
            guard value >= 1, value == value.rounded() else {
                throw MermaidError.semantic("ticks must be a whole number of at least 1", at: valueLocation)
            }
            diagram.ticks = Int(Swift.min(value, Double(RadarDiagram.maximumTicks)))
        case "max": diagram.max = try number()
        case "min": diagram.min = try number()
        default:
            throw MermaidError.syntax("Unknown radar option '\(name)'", at: location)
        }
    }

    mutating func curve() throws {
        let location = scanner.location
        let id = try identifier("a curve id")
        let label = try label()
        scanner.skipWhitespace()
        guard scanner.consume("{") else {
            throw MermaidError.syntax("Expected '{' and the curve's values", at: scanner.location)
        }
        var values: [Double] = []
        var named: [(axis: String, value: Double, location: SourceLocation)] = []
        repeat {
            skipBlank()
            let entryLocation = scanner.location
            if let c = scanner.peek(), c.isLetter || c == "_" {
                guard values.isEmpty else {
                    throw MermaidError.syntax("Mix of plain and axis-named values", at: entryLocation)
                }
                let axis = try identifier("an axis id")
                scanner.skipWhitespace()
                _ = scanner.consume(":")
                scanner.skipWhitespace()
                named.append((axis, try number(), entryLocation))
            } else {
                guard named.isEmpty else {
                    throw MermaidError.syntax("Mix of plain and axis-named values", at: entryLocation)
                }
                values.append(try number())
            }
            skipBlank()
        } while scanner.consume(",")
        guard scanner.consume("}") else { throw MermaidError.syntax("Expected '}' or ','", at: scanner.location) }
        if !named.isEmpty { pending.append((diagram.curves.count, named, location)) }
        diagram.curves.append(.init(id: id, label: label, values: values))
    }

    /// Orders axis-named entries by the axes, as mermaid.js does.
    mutating func resolveReferences() throws {
        for curve in pending {
            for entry in curve.entries where !diagram.axes.contains(where: { $0.id == entry.axis }) {
                throw MermaidError.semantic("Unknown axis '\(entry.axis)'", at: entry.location)
            }
            diagram.curves[curve.index].values = try diagram.axes.map { axis in
                guard let entry = curve.entries.first(where: { $0.axis == axis.id }) else {
                    throw MermaidError.semantic("Missing entry for axis \(axis.label)", at: curve.location)
                }
                return entry.value
            }
        }
    }

    // MARK: - Tokens

    /// `[\w]([-\w]*\w)?`
    mutating func identifier(_ what: String) throws -> String {
        let location = scanner.location
        guard let first = scanner.peek(), first.isWordCharacter else {
            throw MermaidError.syntax("Expected \(what)", at: location)
        }
        var id = scanner.read { $0.isWordCharacter || $0 == "-" }
        while id.hasSuffix("-") { id.removeLast() }
        return id
    }

    /// An optional `["Label"]` (or `['Label']`).
    mutating func label() throws -> String? {
        guard scanner.peek() == "[" else { return nil }
        scanner.advance()
        guard let quote = scanner.peek(), quote == "\"" || quote == "'" else {
            throw MermaidError.syntax("Expected a quoted label inside [ ]", at: scanner.location)
        }
        let start = scanner.location
        scanner.advance()
        var text = ""
        while let c = scanner.peek(), c != quote, c != "\n" {
            scanner.advance()
            if c == "\\", let next = scanner.peek() { text.append(next); scanner.advance() } else { text.append(c) }
        }
        guard scanner.consume(String(quote)) else { throw MermaidError.syntax("Unterminated label", at: start) }
        guard scanner.consume("]") else { throw MermaidError.syntax("Expected ']'", at: scanner.location) }
        return text
    }

    mutating func number() throws -> Double {
        let location = scanner.location
        let text = scanner.read { "+-.0123456789".contains($0) }
        guard !text.isEmpty, let value = Double(text), value.isFinite else {
            throw MermaidError.syntax("Expected a number", at: location)
        }
        return value
    }
}
