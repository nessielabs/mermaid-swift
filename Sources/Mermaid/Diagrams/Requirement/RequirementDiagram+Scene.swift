extension RequirementDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        RequirementSceneBuilder(diagram: self, context: context).build()
    }
}

/// Lays out requirements and elements with the layered layout and joins
/// them with `<<type>>`-labelled relationship lines.
struct RequirementSceneBuilder {
    let diagram: RequirementDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    /// Body lines wrap beyond this width so long requirement texts stay
    /// readable (mermaid.js never wraps them, producing very wide boxes).
    static let bodyWrapWidth = 280.0

    init(diagram: RequirementDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("requirement")
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// One drawable node: a requirement, an element, or a name that only
    /// appears in relationships (drawn as a bare element, leniently).
    struct Node {
        var name: String
        var box: RequirementBox
        var style: ElementStyle
        var role: String
    }

    func resolvedStyle(classes: [String], inline: ElementStyle) -> ElementStyle {
        var style = diagram.classDefinitions["default"] ?? ElementStyle()
        for name in classes { if let def = diagram.classDefinitions[name] { style = style.overlaid(with: def) } }
        return style.overlaid(with: inline)
    }

    func box(stereotype: String, name: String, fields: [(String, String)], style: ElementStyle) -> RequirementBox {
        let font = Font(family: style.fontFamily ?? theme.fontFamily, size: style.fontSize ?? theme.fontSize,
                        bold: style.bold ?? false, italic: style.italic ?? false)
        var bold = font
        bold.bold = true
        let body = fields.filter { !$0.1.isEmpty }.map { label, value in
            TextBlock(LabelParser.parse("\(label): \(value)"), font: font, measurer: context.measurer,
                      maxWidth: Self.bodyWrapWidth, forceWrap: true)
        }
        return RequirementBox(
            stereotype: TextBlock(RichText(plain: "<<\(stereotype)>>"), font: font, measurer: context.measurer),
            name: TextBlock(RichText(plain: name), font: bold, measurer: context.measurer), body: body)
    }

    func nodes() -> [Node] {
        var nodes = diagram.requirements.map { r in
            let style = resolvedStyle(classes: r.classes, inline: r.style)
            let fields = [("ID", r.id), ("Text", r.text), ("Risk", r.risk?.rawValue ?? ""),
                          ("Verification", r.verifyMethod?.rawValue ?? "")]
            return Node(name: r.name, box: box(stereotype: r.kind.rawValue, name: r.name, fields: fields, style: style),
                        style: style, role: "requirement")
        }
        for e in diagram.elements where !nodes.contains(where: { $0.name == e.name }) {
            let style = resolvedStyle(classes: e.classes, inline: e.style)
            nodes.append(Node(name: e.name, box: box(stereotype: "Element", name: e.name,
                                                     fields: [("Type", e.type), ("Doc Ref", e.docRef)], style: style),
                              style: style, role: "element"))
        }
        for relationship in diagram.relationships {
            for name in [relationship.source, relationship.target] where !nodes.contains(where: { $0.name == name }) {
                let style = resolvedStyle(classes: [], inline: ElementStyle())
                nodes.append(Node(name: name, box: box(stereotype: "Element", name: name, fields: [], style: style),
                                  style: style, role: "element"))
            }
        }
        return nodes
    }
}
