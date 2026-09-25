/// The C4 macros and their parameter signatures, as documented by
/// C4-PlantUML and implemented by mermaid.js.
enum C4Macro: Hashable, Sendable {
    case element(C4Diagram.Element.Category, C4Diagram.Element.Form, external: Bool)
    /// A boundary macro with the type it fixes (empty for `Boundary`, whose
    /// type is an argument).
    case boundary(fixedType: String)
    case deploymentNode(TextItem.Alignment?, defaultType: String)
    /// A relationship macro; `indexed` marks `RelIndex`, whose first argument is an index.
    case relationship(C4Diagram.Relationship.Kind, indexed: Bool = false)
    case updateElementStyle
    case updateRelStyle
    case updateLayoutConfig
    /// `AddElementTag`/`AddRelTag`. mermaid.js rejects these C4-PlantUML
    /// statements; they are accepted here so tagged elements pick up styles.
    case addElementTag
    case addRelTag

    init?(name: String) {
        if let macro = Self.table[name] { self = macro } else { return nil }
    }

    /// Whether the macro may be followed by a `{ ... }` block of members.
    var opensBoundary: Bool {
        switch self {
        case .boundary, .deploymentNode: return true
        default: return false
        }
    }

    /// Parameter names in positional order.
    var signature: [String] {
        switch self {
        case .element(let category, _, _):
            return category == .person || category == .system
                ? ["alias", "label", "descr", "sprite", "tags", "link"]
                : ["alias", "label", "techn", "descr", "sprite", "tags", "link"]
        case .boundary(let fixedType):
            return fixedType.isEmpty ? ["alias", "label", "type", "tags", "link"] : ["alias", "label", "tags", "link"]
        case .deploymentNode:
            return ["alias", "label", "type", "descr", "sprite", "tags", "link"]
        case .relationship(_, let indexed):
            let rest = ["from", "to", "label", "techn", "descr", "sprite", "tags", "link"]
            return indexed ? ["index"] + rest : rest
        case .updateElementStyle:
            return ["elementName", "bgColor", "fontColor", "borderColor", "shadowing", "shape", "sprite", "techn",
                    "legendText", "legendSprite"]
        case .updateRelStyle:
            return ["from", "to", "textColor", "lineColor", "offsetX", "offsetY"]
        case .updateLayoutConfig:
            return ["c4ShapeInRow", "c4BoundaryInRow"]
        case .addElementTag:
            return ["tagStereo", "bgColor", "fontColor", "borderColor", "shadowing", "shape", "sprite", "techn",
                    "legendText", "legendSprite"]
        case .addRelTag:
            return ["tagStereo", "textColor", "lineColor", "lineStyle", "sprite", "techn", "legendText", "legendSprite"]
        }
    }

    var displayName: String {
        switch self {
        case .element(let category, _, _): return category.rawValue.capitalized
        case .boundary: return "Boundary"
        case .deploymentNode: return "Deployment_Node"
        case .relationship: return "Rel"
        case .updateElementStyle: return "UpdateElementStyle"
        case .updateRelStyle: return "UpdateRelStyle"
        case .updateLayoutConfig: return "UpdateLayoutConfig"
        case .addElementTag: return "AddElementTag"
        case .addRelTag: return "AddRelTag"
        }
    }

    private static let table: [String: C4Macro] = {
        var table: [String: C4Macro] = [:]
        let categories: [(String, C4Diagram.Element.Category)] = [
            ("System", .system), ("Container", .container), ("Component", .component),
        ]
        for (name, category) in categories {
            table[name] = .element(category, .box, external: false)
            table[name + "Db"] = .element(category, .database, external: false)
            table[name + "Queue"] = .element(category, .queue, external: false)
            table[name + "_Ext"] = .element(category, .box, external: true)
            table[name + "Db_Ext"] = .element(category, .database, external: true)
            table[name + "Queue_Ext"] = .element(category, .queue, external: true)
        }
        table["Person"] = .element(.person, .box, external: false)
        table["Person_Ext"] = .element(.person, .box, external: true)
        table["Boundary"] = .boundary(fixedType: "")
        table["Enterprise_Boundary"] = .boundary(fixedType: "ENTERPRISE")
        table["System_Boundary"] = .boundary(fixedType: "SYSTEM")
        table["Container_Boundary"] = .boundary(fixedType: "CONTAINER")
        table["Deployment_Node"] = .deploymentNode(nil, defaultType: "node")
        table["Node"] = .deploymentNode(nil, defaultType: "node")
        table["Node_L"] = .deploymentNode(.leading, defaultType: "node")
        table["Node_R"] = .deploymentNode(.trailing, defaultType: "node")
        let relationships: [(String, C4Diagram.Relationship.Kind)] = [
            ("Rel", .rel), ("BiRel", .biRel), ("Rel_U", .up), ("Rel_Up", .up), ("Rel_D", .down), ("Rel_Down", .down),
            ("Rel_L", .left), ("Rel_Left", .left), ("Rel_R", .right), ("Rel_Right", .right), ("Rel_Back", .back),
        ]
        for (name, kind) in relationships { table[name] = .relationship(kind) }
        table["RelIndex"] = .relationship(.rel, indexed: true)
        table["UpdateElementStyle"] = .updateElementStyle
        table["UpdateRelStyle"] = .updateRelStyle
        table["UpdateLayoutConfig"] = .updateLayoutConfig
        table["AddElementTag"] = .addElementTag
        table["AddRelTag"] = .addRelTag
        return table
    }()

    /// C4-PlantUML layout and legend statements that mermaid.js documents
    /// as unsupported. They are accepted and ignored so diagrams written
    /// for C4-PlantUML still render.
    static let ignored: Set<String> = [
        "Lay_U", "Lay_Up", "Lay_D", "Lay_Down", "Lay_L", "Lay_Left", "Lay_R", "Lay_Right", "Lay_Distance",
        "SHOW_LEGEND", "SHOW_FLOATING_LEGEND", "LAYOUT_TOP_DOWN", "LAYOUT_LEFT_RIGHT", "LAYOUT_LANDSCAPE",
        "LAYOUT_WITH_LEGEND", "LAYOUT_AS_SKETCH", "HIDE_STEREOTYPE", "SHOW_PERSON_OUTLINE", "SHOW_PERSON_PORTRAIT",
        "SHOW_PERSON_SPRITE", "HIDE_PERSON_SPRITE", "UpdateBoundaryStyle", "UpdateSkinparamsAndLegendEntries",
    ]
}
