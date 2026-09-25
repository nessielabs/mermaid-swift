import Foundation

/// Parses `quadrantChart` source.
///
/// ```
/// quadrantChart
///     title Reach and engagement of campaigns
///     x-axis Low Reach --> High Reach
///     y-axis Low Engagement --> High Engagement
///     quadrant-1 We should expand
///     Campaign A:::hot: [0.3, 0.6] radius: 12, color: #ff3300
///     classDef hot stroke-color: #310085, stroke-width: 4px
/// ```
///
/// Keywords are case-insensitive, as in mermaid.js.
enum QuadrantChartParser {
    static func parse(_ source: DiagramSource) throws -> QuadrantChartDiagram {
        var diagram = QuadrantChartDiagram()
        diagram.accessibility = source.accessibility
        for line in source.lines {
            for (text, offset) in line.text.chartStatements() {
                try statement(text, at: line.location(atOffset: offset), into: &diagram)
            }
        }
        return diagram
    }

    private static func keyword(_ word: String, in text: String) -> String? {
        guard text.count >= word.count, text.prefix(word.count).lowercased() == word else { return nil }
        let rest = text.dropFirst(word.count)
        guard rest.isEmpty || rest.first == " " || rest.first == "\t" else { return nil }
        return String(rest)
    }

    private static func statement(_ text: String, at location: SourceLocation,
                                  into diagram: inout QuadrantChartDiagram) throws {
        if let rest = keyword("title", in: text) {
            diagram.title = rest.chartTextValue
        } else if let rest = keyword("x-axis", in: text) {
            let (low, high) = try axisTexts(rest, at: location)
            diagram.xAxisLeft = low
            diagram.xAxisRight = high
        } else if let rest = keyword("y-axis", in: text) {
            let (low, high) = try axisTexts(rest, at: location)
            diagram.yAxisBottom = low
            diagram.yAxisTop = high
        } else if let index = (1...4).first(where: { keyword("quadrant-\($0)", in: text) != nil }) {
            let rest = keyword("quadrant-\(index)", in: text) ?? ""
            diagram.quadrantLabels[index - 1] = rest.chartTextValue
        } else if let rest = keyword("classdef", in: text) {
            let body = rest.trimmingWhitespace()
            let name = String(body.prefix { !$0.isWhitespace })
            guard !name.isEmpty else { throw MermaidError.syntax("Expected a class name after classDef", at: location) }
            let stylesText = body.dropFirst(name.count)
            let offset = text.count - stylesText.count
            diagram.classes[name] = try styles(String(stylesText), at: SourceLocation(line: location.line, column: location.column + offset))
        } else if let point = try point(text, at: location) {
            diagram.points.append(point)
        } else {
            throw MermaidError.syntax("Unrecognized quadrant chart statement '\(text)'", at: location)
        }
    }

    /// `Low --> High`, `Low -->` (an arrow is appended) or `Low`.
    private static func axisTexts(_ text: String, at location: SourceLocation) throws -> (String?, String?) {
        guard let range = text.range(of: #"-{2,}>"#, options: .regularExpression) else {
            let low = text.chartTextValue
            return (low.isEmpty ? nil : low, nil)
        }
        let low = text[..<range.lowerBound].chartTextValue
        let high = text[range.upperBound...].chartTextValue
        guard !low.isEmpty else { throw MermaidError.syntax("Expected axis text before '-->'", at: location) }
        return high.isEmpty ? (low + " ⟶ ", nil) : (low, high)
    }

    /// `Name(:::class)?: [x, y] styles?`, or nil when the text has no
    /// `: [` point coordinates.
    private static func point(_ text: String, at location: SourceLocation) throws -> QuadrantChartDiagram.Point? {
        let chars = Array(text)
        var quoted = false
        var open: Int?
        var i = 0
        while i < chars.count {
            if chars[i] == "\"" { quoted.toggle() }
            if !quoted, chars[i] == ":" {
                var j = i + 1
                while j < chars.count, chars[j] == " " || chars[j] == "\t" { j += 1 }
                if j < chars.count, chars[j] == "[" { open = j; break }
            }
            i += 1
        }
        guard let open else { return nil }
        let colon = i
        guard let close = chars[open...].firstIndex(of: "]") else {
            throw MermaidError.syntax("Expected ']' after the point coordinates",
                                      at: SourceLocation(line: location.line, column: location.column + chars.count))
        }
        var name = String(chars[..<colon])
        var className: String?
        if let marker = name.range(of: ":::") {
            className = String(name[marker.upperBound...]).trimmingWhitespace()
            name = String(name[..<marker.lowerBound])
            guard let className, !className.isEmpty, className.allSatisfy(\.isWordCharacter) else {
                throw MermaidError.syntax("Expected a class name after ':::'", at: location)
            }
        }
        let label = name.chartTextValue
        guard !label.isEmpty else { throw MermaidError.syntax("Expected a point name before ':'", at: location) }
        let coordinates = String(chars[(open + 1)..<close]).split(separator: ",", omittingEmptySubsequences: false)
        let coordinateLocation = SourceLocation(line: location.line, column: location.column + open + 1)
        guard coordinates.count == 2 else {
            throw MermaidError.syntax("Expected two coordinates [x, y]", at: coordinateLocation)
        }
        var values: [Double] = []
        for (axis, raw) in zip(["x", "y"], coordinates) {
            let text = raw.trimmingWhitespace()
            // mermaid.js' lexer only accepts 0, 1 and 0.xxx; any number in
            // the unit interval is accepted here.
            guard let value = Double(text), text.allSatisfy({ "+-.0123456789".contains($0) }) else {
                throw MermaidError.syntax("Expected a number for \(axis), found '\(text)'", at: coordinateLocation)
            }
            guard (0...1).contains(value) else {
                throw MermaidError.semantic("Point \(axis) value \(text) must be between 0 and 1", at: coordinateLocation)
            }
            values.append(value)
        }
        let styleText = String(chars[(close + 1)...])
        let style = try styles(styleText, at: SourceLocation(line: location.line, column: location.column + close + 1))
        return .init(label: label, x: values[0], y: values[1], className: className, style: style)
    }

    /// Comma-separated `key: value` point styles: `radius`, `color`,
    /// `stroke-color` and `stroke-width`.
    static func styles(_ text: String, at location: SourceLocation) throws -> QuadrantChartDiagram.PointStyle {
        var style = QuadrantChartDiagram.PointStyle()
        for declaration in text.split(separator: ",") {
            let trimmed = declaration.trimmingWhitespace()
            guard !trimmed.isEmpty else { continue }
            guard let (rawKey, rawValue) = trimmed.splitOnce(":") else {
                throw MermaidError.syntax("Expected 'name: value' in point style '\(trimmed)'", at: location)
            }
            let key = rawKey.trimmingWhitespace().lowercased(), value = rawValue.trimmingWhitespace()
            func invalid(_ expected: String) -> MermaidError {
                .semantic("value for \(key) \(value) is invalid, please use a valid \(expected)", at: location)
            }
            switch key {
            case "radius":
                guard let radius = Double(value), radius >= 0, radius.isFinite else { throw invalid("number") }
                style.radius = radius
            case "color", "stroke-color":
                guard let color = Color(css: value) ?? Color(css: "#" + value) else { throw invalid("hex code") }
                if key == "color" { style.color = color } else { style.strokeColor = color }
            case "stroke-width":
                guard value.hasSuffix("px"), let width = Double(value.dropLast(2)), width >= 0 else {
                    throw invalid("number of pixels (eg. 10px)")
                }
                style.strokeWidth = width
            default:
                throw MermaidError.semantic("style named \(key) is not supported.", at: location)
            }
        }
        return style
    }
}
