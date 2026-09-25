extension EntityRelationshipDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        EntityRelationshipSceneBuilder(diagram: self, context: context).build()
    }
}

/// Lays out entities with the layered layout and draws them as tables
/// joined by relationship lines with crow's foot ends.
struct EntityRelationshipSceneBuilder {
    let diagram: EntityRelationshipDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    init(diagram: EntityRelationshipDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("er")
    }

    /// A numeric `er` setting, using mermaid.js' key names and defaults.
    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// Class definitions (with `default` first) overlaid by inline style.
    func resolvedStyle(classes: [String], inline: ElementStyle) -> ElementStyle {
        var style = diagram.classDefinitions["default"] ?? ElementStyle()
        for name in classes { if let def = diagram.classDefinitions[name] { style = style.overlaid(with: def) } }
        return style.overlaid(with: inline)
    }

    func font(_ style: ElementStyle, size: Double? = nil) -> Font {
        Font(family: style.fontFamily ?? theme.fontFamily, size: style.fontSize ?? size ?? theme.fontSize,
             bold: style.bold ?? false, italic: style.italic ?? false)
    }

    /// Plain text (attribute cells are not markdown, so `*id` stays as is).
    func plain(_ text: String, _ style: ElementStyle) -> TextBlock {
        guard !text.isEmpty else { return .empty }
        return TextBlock(RichText(plain: text), font: font(style), measurer: context.measurer)
    }

    func entityBox(_ entity: EntityRelationshipDiagram.Entity, style: ElementStyle) -> EntityBox {
        let name = TextBlock(LabelParser.parse(entity.label), font: font(style), measurer: context.measurer)
        let rows = entity.attributes.map { attribute in
            [plain(attribute.type, style), plain(attribute.name, style),
             plain(attribute.keys.joined(separator: ","), style), plain(attribute.comment, style)]
        }
        return EntityBox(name: name, rows: rows, columnPadding: setting("diagramPadding", 20),
                         rowPadding: setting("entityPadding", 15),
                         minimumSize: Size(setting("minEntityWidth", 100), setting("minEntityHeight", 75)))
    }

    /// Alternating attribute row fills, derived per theme as mermaid.js
    /// does unless `rowOdd`/`rowEven` are set.
    var rowFills: (odd: Color, even: Color) {
        let main = theme.mainBkg
        let derived: (Color, Color)
        switch theme.name {
        case .dark: derived = (main.lightened(5), main.darkened(10))
        case .neutral: derived = (main.lightened(75), Color(hex: 0xF4F4F4))
        case .forest: derived = (main.lightened(75), main.lightened(20))
        case .base where theme.background.isDark: derived = (main.darkened(5), main.darkened(10))
        case .base: derived = (main.lightened(75), main.lightened(5))
        case .default: derived = (theme.primaryColor.lightened(75), theme.primaryColor.lightened(1))
        }
        return (theme.color("rowOdd", default: derived.0), theme.color("rowEven", default: derived.1))
    }
}
