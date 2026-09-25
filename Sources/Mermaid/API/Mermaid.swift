/// The entry point for parsing and rendering Mermaid source.
///
/// ```swift
/// let scene = try Mermaid.render("flowchart LR\n  A --> B")
/// let svg = scene.svg
/// let png = scene.pngData()
/// ```
public enum Mermaid {
    /// Parses source into a diagram without laying it out.
    public static func parse(_ source: String) throws -> ParsedDiagram {
        let prepared = try Preprocessor.prepare(source)
        guard let header = prepared.header else {
            throw MermaidError(.emptyDiagram, "No diagram found")
        }
        let keyword = headerKeyword(header.text)
        guard let entry = DiagramRegistry.entry(for: keyword) else {
            throw MermaidError(.unknownDiagramType(keyword), "Unknown diagram type '\(keyword)'", at: header.location)
        }
        let diagram = try entry.parse(DiagramSource(prepared: prepared, header: header))
        return ParsedDiagram(diagram: diagram, title: prepared.title, config: prepared.config)
    }

    /// Parses and lays out source into a drawable scene.
    public static func render(_ source: String, options: RenderOptions = RenderOptions()) throws -> Scene {
        try parse(source).scene(options: options)
    }

    /// The diagram type declared by `source`, or nil if none is recognized.
    public static func detectType(_ source: String) -> DiagramType? {
        guard let header = try? Preprocessor.prepare(source).header else { return nil }
        return DiagramRegistry.entry(for: headerKeyword(header.text))?.type
    }

    /// The diagram types this library can parse and render.
    public static var supportedTypes: [DiagramType] { DiagramRegistry.entries.map(\.type) }

    static func headerKeyword(_ header: String) -> String {
        String(header.prefix { !$0.isWhitespace && $0 != ":" && $0 != "{" })
    }
}

/// A parsed diagram together with its document-level settings.
public struct ParsedDiagram: Sendable {
    public var diagram: any Diagram
    /// The front matter title.
    public var title: String?
    /// Merged front matter and directive configuration.
    public var config: ConfigValue

    public var type: DiagramType { Swift.type(of: diagram).type }

    /// Lays the diagram out with the given options.
    public func scene(options: RenderOptions = RenderOptions()) throws -> Scene {
        let theme = options.theme ?? Theme(config: config)
        let context = RenderContext(theme: theme, measurer: options.measurer, config: config, title: title)
        var scene = try diagram.scene(in: context)
        switch options.background {
        case .theme: scene.background = theme.background
        case .transparent: scene.background = nil
        case .color(let color): scene.background = color
        }
        scene.accessibilityTitle = diagram.accessibility.title ?? title ?? scene.accessibilityTitle
        scene.accessibilityDescription = diagram.accessibility.description ?? scene.accessibilityDescription
        return scene
    }
}

public struct RenderOptions: Sendable {
    public enum Background: Hashable, Sendable {
        /// The theme's background color.
        case theme
        case transparent
        case color(Color)
    }

    /// Overrides the theme selected by the diagram's configuration.
    public var theme: Theme?
    public var measurer: any TextMeasurer
    public var background: Background

    public init(theme: Theme? = nil, measurer: any TextMeasurer = defaultTextMeasurer(),
                background: Background = .theme) {
        self.theme = theme
        self.measurer = measurer
        self.background = background
    }
}

/// Maps header keywords to diagram parsers.
struct DiagramRegistry {
    struct Entry: Sendable {
        var type: DiagramType
        var keywords: [String]
        var parse: @Sendable (DiagramSource) throws -> any Diagram
    }

    static let entries: [Entry] = [
        Entry(type: .flowchart, keywords: ["flowchart", "graph", "flowchart-elk"]) { try FlowchartParser.parse($0) },
        Entry(type: .classDiagram, keywords: ["classDiagram", "classDiagram-v2"]) { try ClassParser.parse($0) },
        Entry(type: .entityRelationship, keywords: ["erDiagram"]) { try EntityRelationshipParser.parse($0) },
        Entry(type: .requirement, keywords: ["requirementDiagram"]) { try RequirementParser.parse($0) },
        Entry(type: .sequence, keywords: ["sequenceDiagram"]) { try SequenceParser.parse($0) },
        Entry(type: .state, keywords: ["stateDiagram", "stateDiagram-v2"]) { try StateParser.parse($0) },
        Entry(type: .architecture, keywords: ["architecture-beta", "architecture"]) { try ArchitectureParser.parse($0) },
        Entry(type: .c4, keywords: C4Diagram.Kind.allCases.map(\.rawValue)) { try C4Parser.parse($0) },
        Entry(type: .gantt, keywords: ["gantt"]) { try GanttParser.parse($0) },
        Entry(type: .timeline, keywords: ["timeline"]) { try TimelineParser.parse($0) },
        Entry(type: .journey, keywords: ["journey"]) { try JourneyParser.parse($0) },
        Entry(type: .kanban, keywords: ["kanban"]) { try KanbanParser.parse($0) },
        Entry(type: .pie, keywords: ["pie"]) { try PieParser.parse($0) },
        Entry(type: .quadrantChart, keywords: ["quadrantChart"]) { try QuadrantChartParser.parse($0) },
        Entry(type: .xyChart, keywords: ["xychart", "xychart-beta"]) { try XYChartParser.parse($0) },
        Entry(type: .radar, keywords: ["radar-beta", "radar"]) { try RadarParser.parse($0) },
        Entry(type: .sankey, keywords: ["sankey", "sankey-beta"]) { try SankeyParser.parse($0) },
    ]

    static func entry(for keyword: String) -> Entry? {
        let lower = keyword.lowercased()
        return entries.first { $0.keywords.contains { $0.lowercased() == lower } }
    }
}
