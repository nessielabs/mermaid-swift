import Foundation

/// Parses `xychart` and `xychart-beta` source.
///
/// ```
/// xychart horizontal
///     title "Sales Revenue"
///     x-axis Months [jan, feb, "mar 2024"]
///     y-axis "Revenue (in $)" 4000 --> 11000
///     bar [5000, 6000, 7500]
///     line "trend" [5000 "start", 6000, 7500 "peak"]
/// ```
///
/// Keywords are case-insensitive and `;` separates statements, as in the
/// jison grammar. Deliberate leniency: unquoted titles may contain
/// spaces (mermaid.js requires quotes for multi-word text).
enum XYChartParser {
    static func parse(_ source: DiagramSource) throws -> XYChartDiagram {
        var diagram = XYChartDiagram()
        diagram.accessibility = source.accessibility
        let orientation = source.headerArguments.strippingInlineComment()
        switch orientation.lowercased() {
        case "": break
        case "vertical": diagram.orientation = .vertical
        case "horizontal": diagram.orientation = .horizontal
        default:
            let offset = source.header.text.count - source.headerArguments.count
            throw MermaidError.syntax("Unknown orientation '\(orientation)'; expected vertical or horizontal",
                                      at: source.header.location(atOffset: offset))
        }
        for line in source.lines {
            for (text, offset) in line.text.chartStatements() {
                try statement(text, at: line.location(atOffset: offset), into: &diagram)
            }
        }
        guard !diagram.series.isEmpty else {
            throw MermaidError.semantic("No plot to render; add a bar or line with some data", at: source.header.location)
        }
        return diagram
    }

    private static func keyword(_ word: String, in text: String) -> String? {
        guard text.count >= word.count, text.prefix(word.count).lowercased() == word else { return nil }
        let rest = text.dropFirst(word.count)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" || rest.first == "[" || rest.first == "\"" else {
            return nil
        }
        return String(rest.drop { $0 == " " || $0 == "\t" })
    }

    private static func statement(_ text: String, at location: SourceLocation, into diagram: inout XYChartDiagram) throws {
        /// The location of `rest` within the statement.
        func locate(_ rest: String) -> SourceLocation {
            SourceLocation(line: location.line, column: location.column + text.count - rest.count)
        }
        if let rest = keyword("title", in: text) {
            diagram.title = rest.chartTextValue
        } else if let rest = keyword("x-axis", in: text) {
            let (title, data) = try axis(rest, allowCategories: true, at: locate(rest))
            if let title { diagram.xAxisTitle = title }
            if let data { diagram.xAxis = data }
        } else if let rest = keyword("y-axis", in: text) {
            let (title, data) = try axis(rest, allowCategories: false, at: locate(rest))
            if let title { diagram.yAxisTitle = title }
            if case .range(let range) = data { diagram.yAxisRange = range }
        } else if let rest = keyword("line", in: text) {
            diagram.series.append(try series(.line, rest, at: locate(rest)))
        } else if let rest = keyword("bar", in: text) {
            diagram.series.append(try series(.bar, rest, at: locate(rest)))
        } else {
            throw MermaidError.syntax("Unrecognized XY chart statement '\(text)'", at: location)
        }
    }

    /// Index of the first `[` outside double quotes.
    private static func openingBracket(in chars: [Character]) -> Int? {
        var quoted = false
        for (i, c) in chars.enumerated() {
            if c == "\"" { quoted.toggle() } else if c == "[", !quoted { return i }
        }
        return nil
    }

    private static let numberPattern = #"[+-]?(?:\d+(?:\.\d+)?|\.\d+)"#
    // An optional title, then `min --> max` ending the statement.
    // A constant, valid pattern: `try!` cannot fail.
    private static let rangePattern = try! NSRegularExpression(
        pattern: "^(.*?)\\s*(\(numberPattern))\\s*-{2,}>\\s*(\(numberPattern))$")

    /// An optional title followed by `[categories]` or `min --> max`.
    private static func axis(_ text: String, allowCategories: Bool,
                             at location: SourceLocation) throws -> (String?, XYChartDiagram.XAxisData?) {
        let chars = Array(text)
        if let open = openingBracket(in: chars) {
            let bracketLocation = SourceLocation(line: location.line, column: location.column + open)
            guard allowCategories else {
                throw MermaidError.syntax("The y-axis takes a numeric range such as 0 --> 100, not categories",
                                          at: bracketLocation)
            }
            let title = String(chars[..<open]).chartTextValue
            let inner = try bracketContents(chars, open: open, at: location)
            let categories = split(inner).map(\.text.chartTextValue)
            guard !categories.contains(where: \.isEmpty) else {
                throw MermaidError.syntax("Expected a category name", at: bracketLocation)
            }
            return (title.isEmpty ? nil : title, .categories(categories))
        }
        let trimmed = text.trimmingWhitespace() as NSString
        if let match = rangePattern.firstMatch(in: trimmed as String, range: NSRange(location: 0, length: trimmed.length)),
           let start = Double(trimmed.substring(with: match.range(at: 2))),
           let end = Double(trimmed.substring(with: match.range(at: 3))) {
            let title = trimmed.substring(with: match.range(at: 1)).chartTextValue
            return (title.isEmpty ? nil : title, .range(.init(start, end)))
        }
        if text.contains("-->") {
            throw MermaidError.syntax("Expected a numeric range such as 0 --> 100", at: location)
        }
        let title = text.chartTextValue
        return (title.isEmpty ? nil : title, nil)
    }

    /// `[title] [values]`, where a value may carry a quoted point label.
    private static func series(_ kind: XYChartDiagram.Series.Kind, _ text: String,
                               at location: SourceLocation) throws -> XYChartDiagram.Series {
        let chars = Array(text)
        guard let open = openingBracket(in: chars) else {
            throw MermaidError.syntax("Expected data such as [1, 2, 3] after '\(kind.rawValue)'",
                                      at: SourceLocation(line: location.line, column: location.column + chars.count))
        }
        let title = String(chars[..<open]).chartTextValue
        let inner = try bracketContents(chars, open: open, at: location)
        var values: [Double] = [], labels: [String?] = []
        for item in split(inner) {
            let itemLocation = SourceLocation(line: location.line, column: location.column + open + 1 + item.offset)
            let parts = item.text.trimmingWhitespace()
            let numberText = String(parts.prefix { !$0.isWhitespace && $0 != "\"" })
            guard numberText.range(of: "^\(numberPattern)$", options: .regularExpression) != nil,
                  let value = Double(numberText) else {
                throw MermaidError.syntax("Expected a number, found '\(parts)'", at: itemLocation)
            }
            let rest = parts.dropFirst(numberText.count).trimmingWhitespace()
            if rest.isEmpty {
                labels.append(nil)
            } else if rest.count >= 2, rest.hasPrefix("\""), rest.hasSuffix("\"") {
                labels.append(rest.unquoted)
            } else {
                throw MermaidError.syntax("Expected a quoted point label after \(numberText)", at: itemLocation)
            }
            values.append(value)
        }
        return .init(kind: kind, title: title.isEmpty ? nil : title, values: values,
                     pointLabels: labels.contains { $0 != nil } ? labels : [])
    }

    /// The text between `[` at `open` and its `]`, which must end the
    /// statement.
    private static func bracketContents(_ chars: [Character], open: Int, at location: SourceLocation) throws -> String {
        var quoted = false
        for i in (open + 1)..<chars.count {
            if chars[i] == "\"" { quoted.toggle() } else if chars[i] == "]", !quoted {
                let trailing = String(chars[(i + 1)...]).trimmingWhitespace()
                guard trailing.isEmpty else {
                    throw MermaidError.syntax("Unexpected '\(trailing)' after ']'",
                                              at: SourceLocation(line: location.line, column: location.column + i + 1))
                }
                let inner = String(chars[(open + 1)..<i])
                guard !inner.trimmingWhitespace().isEmpty else {
                    throw MermaidError.syntax("Expected at least one value inside [ ]",
                                              at: SourceLocation(line: location.line, column: location.column + open))
                }
                return inner
            }
        }
        throw MermaidError.syntax("Expected ']'", at: SourceLocation(line: location.line, column: location.column + chars.count))
    }

    /// Comma-separated items outside double quotes, with offsets.
    private static func split(_ text: String) -> [(text: String, offset: Int)] {
        var items: [(String, Int)] = []
        var current = "", start = 0, quoted = false
        for (i, c) in text.enumerated() {
            if c == "\"" { quoted.toggle() }
            if c == ",", !quoted {
                items.append((current, start))
                current = ""
                start = i + 1
            } else {
                current.append(c)
            }
        }
        items.append((current, start))
        return items.map { text, start in (text, start + text.prefix { $0 == " " || $0 == "\t" }.count) }
    }
}
