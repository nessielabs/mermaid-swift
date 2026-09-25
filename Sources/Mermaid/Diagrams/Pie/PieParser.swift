/// Parses `pie` source.
///
/// ```
/// pie showData title Pets adopted by volunteers
///     "Dogs" : 386
///     'Cats' : 85.5
/// ```
enum PieParser {
    static func parse(_ source: DiagramSource) throws -> PieDiagram {
        var diagram = PieDiagram()
        diagram.accessibility = source.accessibility
        var seen: Set<String> = []

        // The header may carry `showData` and then any statement, such as
        // the title (`pie showData title Key elements`).
        var header = source.headerArguments.strippingInlineComment()
        let headerOffset = source.header.text.count - source.headerArguments.count
        var consumed = 0
        if header.hasPrefix("showData"), header.dropFirst(8).first.map({ $0 == " " || $0 == "\t" }) ?? true {
            diagram.showData = true
            let rest = header.dropFirst(8)
            consumed = 8 + rest.prefix { $0 == " " || $0 == "\t" }.count
            header = rest.trimmingWhitespace()
        }
        if !header.isEmpty {
            try statement(header, at: source.header.location(atOffset: headerOffset + consumed),
                          into: &diagram, seen: &seen)
        }
        for line in source.lines {
            try statement(line.text.strippingInlineComment(), at: line.location, into: &diagram, seen: &seen)
        }
        return diagram
    }

    private static func statement(_ text: String, at location: SourceLocation,
                                  into diagram: inout PieDiagram, seen: inout Set<String>) throws {
        if text == "title" || text.hasPrefix("title ") || text.hasPrefix("title\t") {
            diagram.title = text.dropFirst(5).chartTextValue
            return
        }
        guard let quote = text.first, quote == "\"" || quote == "'" else {
            throw MermaidError.syntax("Expected a quoted slice label such as \"Dogs\" : 42", at: location)
        }
        guard let close = closingQuote(in: text, quote: quote) else {
            throw MermaidError.syntax("Unterminated slice label", at: location)
        }
        let label = unescape(String(text[text.index(after: text.startIndex)..<close])).trimmingWhitespace()
        var rest = text[text.index(after: close)...].trimmingWhitespace()
        let colonColumn = location.column + text.distance(from: text.startIndex, to: close) + 1
        guard rest.hasPrefix(":") else {
            throw MermaidError.syntax("Expected ':' after the slice label",
                                      at: SourceLocation(line: location.line, column: colonColumn))
        }
        rest = String(rest.dropFirst()).trimmingWhitespace()
        let valueColumn = location.column + text.count - rest.count
        let valueLocation = SourceLocation(line: location.line, column: valueColumn)
        guard let value = number(rest) else {
            throw MermaidError.syntax("Expected a number for slice '\(label)', found '\(rest)'", at: valueLocation)
        }
        guard value >= 0 else {
            throw MermaidError.semantic(
                "\"\(label)\" has invalid value: \(ChartNumber.format(value)). Negative values are not allowed in pie charts. All slice values must be >= 0.",
                at: valueLocation)
        }
        if seen.insert(label).inserted {
            diagram.slices.append(.init(label: label, value: value))
        }
    }

    /// A decimal number. Mermaid's grammar requires digits before any
    /// decimal point; this also accepts `.5`, `+3` and exponents, and
    /// rejects anything non-finite.
    static func number(_ text: String) -> Double? {
        guard !text.isEmpty, text.allSatisfy({ "+-.0123456789eE".contains($0) }),
              let value = Double(text), value.isFinite else { return nil }
        return value
    }

    private static func closingQuote(in text: String, quote: Character) -> String.Index? {
        var i = text.index(after: text.startIndex)
        while i < text.endIndex {
            if text[i] == "\\" {
                i = text.index(after: i)
                if i < text.endIndex { i = text.index(after: i) }
                continue
            }
            if text[i] == quote { return i }
            i = text.index(after: i)
        }
        return nil
    }

    private static func unescape(_ text: String) -> String {
        var out = ""
        var escaping = false
        for c in text {
            if escaping { out.append(c); escaping = false } else if c == "\\" { escaping = true } else { out.append(c) }
        }
        return out
    }
}
