/// The resolved colors and fonts used to draw diagrams.
///
/// A theme starts from one of Mermaid's named themes and applies any
/// `themeVariables` from configuration. Every property uses the variable
/// name Mermaid documents, so overrides written for mermaid.js carry over
/// unchanged. Diagram types read the variables they need; variables the
/// theme does not model directly are available through `color(_:)`.
public struct Theme: Hashable, Sendable {
    public enum Name: String, CaseIterable, Sendable {
        case `default`, neutral, dark, forest, base
    }

    public var name: Name
    public var fontFamily: String
    public var fontSize: Double

    public var background: Color
    public var primaryColor: Color
    public var primaryTextColor: Color
    public var primaryBorderColor: Color
    public var secondaryColor: Color
    public var secondaryTextColor: Color
    public var secondaryBorderColor: Color
    public var tertiaryColor: Color
    public var tertiaryTextColor: Color
    public var tertiaryBorderColor: Color

    public var textColor: Color
    public var lineColor: Color
    public var mainBkg: Color
    public var nodeBorder: Color
    public var nodeTextColor: Color
    public var clusterBkg: Color
    public var clusterBorder: Color
    public var titleColor: Color
    public var edgeLabelBackground: Color
    public var noteBkgColor: Color
    public var noteBorderColor: Color
    public var noteTextColor: Color

    /// Twelve section colors (`cScale0`...`cScale11`) used by mindmap,
    /// timeline, journey, kanban, and other section-colored diagrams.
    public var sectionColors: [Color]
    /// Twelve pie slice colors (`pie1`...`pie12`).
    public var pieColors: [Color]

    /// Theme variables that are not modeled as properties, keyed by their
    /// Mermaid name (for example `actorBkg` or `git0`).
    public var extras: [String: Color] = [:]

    /// Looks up any theme variable by its Mermaid name.
    public func color(_ variable: String) -> Color? {
        if let value = extras[variable] { return value }
        switch variable {
        case "background": return background
        case "primaryColor": return primaryColor
        case "primaryTextColor": return primaryTextColor
        case "primaryBorderColor": return primaryBorderColor
        case "secondaryColor": return secondaryColor
        case "secondaryTextColor": return secondaryTextColor
        case "secondaryBorderColor": return secondaryBorderColor
        case "tertiaryColor": return tertiaryColor
        case "tertiaryTextColor": return tertiaryTextColor
        case "tertiaryBorderColor": return tertiaryBorderColor
        case "textColor": return textColor
        case "lineColor": return lineColor
        case "mainBkg": return mainBkg
        case "nodeBorder": return nodeBorder
        case "nodeTextColor": return nodeTextColor
        case "clusterBkg": return clusterBkg
        case "clusterBorder": return clusterBorder
        case "titleColor": return titleColor
        case "edgeLabelBackground": return edgeLabelBackground
        case "noteBkgColor": return noteBkgColor
        case "noteBorderColor": return noteBorderColor
        case "noteTextColor": return noteTextColor
        default:
            if variable.hasPrefix("cScale"), let i = Int(variable.dropFirst(6)), sectionColors.indices.contains(i) {
                return sectionColors[i]
            }
            if variable.hasPrefix("pie"), let i = Int(variable.dropFirst(3)), pieColors.indices.contains(i - 1) {
                return pieColors[i - 1]
            }
            return nil
        }
    }

    /// Looks up a theme variable, falling back when it is not defined.
    public func color(_ variable: String, default fallback: Color) -> Color {
        color(variable) ?? fallback
    }
}
