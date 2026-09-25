/// Every diagram type Mermaid defines.
public enum DiagramType: String, CaseIterable, Hashable, Sendable {
    case flowchart
    case sequence
    case classDiagram = "class"
    case state
    case entityRelationship = "er"
    case gantt
    case pie
    case journey
    case gitGraph
    case mindmap
    case timeline
    case quadrantChart
    case xyChart
    case sankey
    case requirement
    case c4
    case block
    case packet
    case kanban
    case architecture
    case radar
    case treemap
}

/// Everything a diagram needs to lay itself out.
public struct RenderContext: Sendable {
    public var theme: Theme
    public var measurer: any TextMeasurer
    /// Merged front matter and directive configuration.
    public var config: ConfigValue
    /// The front matter title, if any.
    public var title: String?

    public init(theme: Theme = .default, measurer: any TextMeasurer = defaultTextMeasurer(),
                config: ConfigValue = .object([:]), title: String? = nil) {
        self.theme = theme
        self.measurer = measurer
        self.config = config
        self.title = title
    }

    /// Configuration for a diagram type, such as `config.flowchart`.
    public func section(_ name: String) -> ConfigValue { config[name] ?? .object([:]) }

    /// The theme's base font at `size` (defaulting to the theme size).
    public func font(size: Double? = nil, bold: Bool = false) -> Font {
        Font(family: theme.fontFamily, size: size ?? theme.fontSize, bold: bold)
    }

    /// Lays out label text in the theme font.
    public func text(_ rich: RichText, size: Double? = nil, bold: Bool = false,
                     maxWidth: Double? = nil, forceWrap: Bool = false) -> TextBlock {
        TextBlock(rich, font: font(size: size, bold: bold), measurer: measurer,
                  maxWidth: maxWidth, forceWrap: forceWrap)
    }

    /// Parses and lays out a raw label in the theme font.
    public func label(_ raw: String, size: Double? = nil, bold: Bool = false,
                      maxWidth: Double? = nil, forceWrap: Bool = false) -> TextBlock {
        text(LabelParser.parse(raw), size: size, bold: bold, maxWidth: maxWidth, forceWrap: forceWrap)
    }
}

/// A parsed diagram of any type.
public protocol Diagram: Sendable {
    static var type: DiagramType { get }
    /// Accessible title and description declared with `accTitle`/`accDescr`.
    var accessibility: Accessibility { get }
    /// Lays the diagram out into a drawable scene.
    func scene(in context: RenderContext) throws -> Scene
}

public struct Accessibility: Hashable, Sendable {
    public var title: String?
    public var description: String?

    public init(title: String? = nil, description: String? = nil) {
        self.title = title
        self.description = description
    }
}
