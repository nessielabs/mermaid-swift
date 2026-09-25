/// The node shapes Mermaid supports, covering the classic bracket syntax
/// and the named shapes of the `A@{ shape: ... }` syntax.
public enum NodeShape: String, Hashable, Sendable, CaseIterable {
    case rect, rounded, stadium, subroutine, cylinder, circle, doubleCircle, diamond, hexagon
    case leanRight, leanLeft, trapezoid, invertedTrapezoid, asymmetric
    case notchedRect, linedRect, smallCircle, framedCircle, filledCircle, forkJoin, hourglass
    case braceLeft, braceRight, braces, bolt, document, delay, horizontalCylinder, linedCylinder
    case curvedTrapezoid, dividedRect, documents, stackedRect, flag, triangle, windowPane
    case linedDocument, notchedPentagon, bowTieRect, crossedCircle, taggedDocument, taggedRect
    case text, slopedRect, flippedTriangle

    /// Resolves a shape name or alias from the `@{ shape: ... }` syntax.
    public init?(name: String) {
        guard let shape = Self.aliases[name.lowercased()] else { return nil }
        self = shape
    }

    static let aliases: [String: NodeShape] = {
        let table: [(NodeShape, [String])] = [
            (.rect, ["rect", "square", "proc", "process", "rectangle"]),
            (.rounded, ["rounded", "event"]),
            (.stadium, ["stadium", "pill", "terminal"]),
            (.subroutine, ["subroutine", "fr-rect", "subproc", "framed-rectangle", "subprocess"]),
            (.cylinder, ["cyl", "cylinder", "database", "db"]),
            (.circle, ["circle", "circ"]),
            (.doubleCircle, ["dbl-circ", "double-circle"]),
            (.diamond, ["diam", "diamond", "decision", "question", "rhombus"]),
            (.hexagon, ["hex", "hexagon", "prepare"]),
            (.leanRight, ["lean-r", "lean-right", "in-out"]),
            (.leanLeft, ["lean-l", "lean-left", "out-in"]),
            (.trapezoid, ["trap-b", "trapezoid", "priority", "trapezoid-bottom"]),
            (.invertedTrapezoid, ["trap-t", "inv-trapezoid", "manual", "trapezoid-top"]),
            (.asymmetric, ["odd", "asymmetric"]),
            (.notchedRect, ["notch-rect", "card", "notched-rectangle"]),
            (.linedRect, ["lin-rect", "lined-rectangle", "lin-proc", "lined-process", "shaded-process"]),
            (.smallCircle, ["sm-circ", "small-circle", "start"]),
            (.framedCircle, ["fr-circ", "framed-circle", "stop"]),
            (.filledCircle, ["f-circ", "filled-circle", "junction"]),
            (.forkJoin, ["fork", "join"]),
            (.hourglass, ["hourglass", "collate"]),
            (.braceLeft, ["brace", "brace-l", "comment"]),
            (.braceRight, ["brace-r"]),
            (.braces, ["braces"]),
            (.bolt, ["bolt", "com-link", "lightning-bolt"]),
            (.document, ["doc", "document"]),
            (.delay, ["delay", "half-rounded-rectangle"]),
            (.horizontalCylinder, ["h-cyl", "das", "horizontal-cylinder"]),
            (.linedCylinder, ["lin-cyl", "disk", "lined-cylinder"]),
            (.curvedTrapezoid, ["curv-trap", "display", "curved-trapezoid"]),
            (.dividedRect, ["div-rect", "div-proc", "divided-rectangle", "divided-process"]),
            (.documents, ["docs", "documents", "st-doc", "stacked-document"]),
            (.stackedRect, ["st-rect", "procs", "processes", "stacked-rectangle"]),
            (.flag, ["flag", "paper-tape"]),
            (.triangle, ["tri", "extract", "triangle"]),
            (.windowPane, ["win-pane", "internal-storage", "window-pane"]),
            (.linedDocument, ["lin-doc", "lined-document"]),
            (.notchedPentagon, ["notch-pent", "loop-limit", "notched-pentagon"]),
            (.bowTieRect, ["bow-rect", "stored-data", "bow-tie-rectangle"]),
            (.crossedCircle, ["cross-circ", "summary", "crossed-circle"]),
            (.taggedDocument, ["tag-doc", "tagged-document"]),
            (.taggedRect, ["tag-rect", "tag-proc", "tagged-rectangle", "tagged-process"]),
            (.text, ["text"]),
            (.slopedRect, ["sl-rect", "manual-input", "sloped-rectangle"]),
            (.flippedTriangle, ["flip-tri", "manual-file", "flipped-triangle"]),
        ]
        var result: [String: NodeShape] = [:]
        for (shape, names) in table { for name in names { result[name] = shape } }
        return result
    }()

    /// Shapes drawn at a fixed size that never show their label inside.
    public var isLabelless: Bool {
        switch self {
        case .smallCircle, .framedCircle, .filledCircle, .forkJoin, .crossedCircle: return true
        default: return false
        }
    }

    /// The node size needed to fit a label of `label` size with `padding`
    /// between the text and the shape's edge.
    public func size(forLabel label: Size, padding p: Double) -> Size {
        let w = label.width + 2 * p, h = label.height + 2 * p
        switch self {
        case .rect, .rounded, .notchedRect, .linedRect, .dividedRect, .windowPane, .taggedRect: return Size(w, h)
        case .text: return Size(label.width + 8, label.height + 8)
        case .stadium: return Size(w + h / 2, h)
        case .subroutine: return Size(w + 16, h)
        case .cylinder, .linedCylinder: return Size(w, h + 2 * Self.capHeight(width: w))
        case .horizontalCylinder: return Size(w + h / 2, h)
        case .circle: let d = max(label.width, label.height) + 2 * p; return Size(d, d)
        case .doubleCircle: let d = max(label.width, label.height) + 2 * p + 10; return Size(d, d)
        case .diamond: let s = label.width + label.height + 2 * p; return Size(s, s)
        case .hexagon: return Size(w + h / 2, h)
        case .leanRight, .leanLeft, .trapezoid, .invertedTrapezoid: return Size(w + h / 2, h)
        case .asymmetric: return Size(w + h / 4, h)
        case .smallCircle, .filledCircle: return Size(14, 14)
        case .framedCircle, .crossedCircle: return Size(22, 22)
        case .forkJoin: return Size(70, 10)
        case .hourglass: return Size(30, 30)
        case .braceLeft, .braceRight: return Size(w + 12, h)
        case .braces: return Size(w + 24, h)
        case .bolt: return Size(max(w * 0.6, 40), max(h, 60))
        case .document, .linedDocument, .taggedDocument: return Size(w, h + h / 4)
        case .documents: return Size(w + 10, h + h / 4 + 10)
        case .stackedRect: return Size(w + 10, h + 10)
        case .delay: return Size(w + h / 2, h)
        case .curvedTrapezoid: return Size(w + h / 2, h)
        case .flag: return Size(w, h + h / 4)
        case .triangle, .flippedTriangle: return Size(w * 1.5 + h, (w * 1.5 + h) * 0.75)
        case .notchedPentagon: return Size(w + h / 2, h)
        case .bowTieRect: return Size(w + h / 2, h)
        case .slopedRect: return Size(w, h + h / 4)
        }
    }

    static func capHeight(width: Double) -> Double { (width / 2) / (2.5 + width / 50) }
}
