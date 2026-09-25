import Foundation

/// Visual overrides for a node, edge, or cluster, parsed from the CSS-like
/// declarations of `style`, `classDef`, and `linkStyle` statements.
/// Unset properties fall back to the theme.
public struct ElementStyle: Hashable, Sendable {
    public var fill: Color?
    public var stroke: Color?
    public var strokeWidth: Double?
    public var strokeDash: [Double]?
    public var textColor: Color?
    public var fontSize: Double?
    public var fontFamily: String?
    public var bold: Bool?
    public var italic: Bool?
    public var opacity: Double?
    public var cornerRadius: Double?

    public init() {}

    public var isEmpty: Bool { self == ElementStyle() }

    /// Parses declarations such as `fill:#f9f,stroke:#333,stroke-width:4px`.
    /// Commas inside parentheses (as in `rgb(1, 2, 3)`) do not split, `;`
    /// is accepted as a separator, and unknown properties are ignored as
    /// browsers do.
    public init(css: String) {
        self.init()
        for declaration in Self.split(css) {
            guard let (rawName, rawValue) = declaration.splitOnce(":") else { continue }
            let value = rawValue.replacingOccurrences(of: "!important", with: "").trimmingWhitespace()
            apply(name: rawName.trimmingWhitespace().lowercased(), value: value)
        }
    }

    private mutating func apply(name: String, value: String) {
        switch name {
        case "fill", "background", "background-color": fill = Color(css: value) ?? (value == "none" ? .clear : fill)
        case "stroke", "border-color": stroke = Color(css: value) ?? (value == "none" ? .clear : stroke)
        case "stroke-width", "border-width": strokeWidth = Self.length(value)
        case "stroke-dasharray":
            let parts = value.split(whereSeparator: { $0 == " " || $0 == "," }).compactMap { Self.length(String($0)) }
            strokeDash = parts.isEmpty ? nil : parts
        case "color": textColor = Color(css: value)
        case "font-size": fontSize = Self.length(value)
        case "font-family": fontFamily = value.replacingOccurrences(of: "\"", with: "")
        case "font-weight": bold = value == "bold" || value == "bolder" || (Double(value).map { $0 >= 600 } ?? false)
        case "font-style": italic = value == "italic" || value == "oblique"
        case "opacity": opacity = Double(value)
        case "rx", "ry", "border-radius": cornerRadius = Self.length(value)
        default: break
        }
    }

    /// Returns a style whose set properties override this one's.
    public func overlaid(with other: ElementStyle) -> ElementStyle {
        var result = self
        result.fill = other.fill ?? fill
        result.stroke = other.stroke ?? stroke
        result.strokeWidth = other.strokeWidth ?? strokeWidth
        result.strokeDash = other.strokeDash ?? strokeDash
        result.textColor = other.textColor ?? textColor
        result.fontSize = other.fontSize ?? fontSize
        result.fontFamily = other.fontFamily ?? fontFamily
        result.bold = other.bold ?? bold
        result.italic = other.italic ?? italic
        result.opacity = other.opacity ?? opacity
        result.cornerRadius = other.cornerRadius ?? cornerRadius
        return result
    }

    static func length(_ text: String) -> Double? {
        let digits = text.trimmingWhitespace().replacingOccurrences(of: "px", with: "")
        return Double(digits)
    }

    static func split(_ css: String) -> [String] {
        var parts: [String] = []
        var current = ""
        var depth = 0
        for c in css {
            switch c {
            case "(": depth += 1; current.append(c)
            case ")": depth -= 1; current.append(c)
            case "," where depth == 0, ";" where depth == 0:
                parts.append(current)
                current = ""
            default: current.append(c)
            }
        }
        parts.append(current)
        return parts.map { $0.trimmingWhitespace() }.filter { !$0.isEmpty }
    }
}
