/// A measured C4 element: its size, outline shape, and stacked text lines
/// (`«type»`, optional person glyph, bold name, `[technology]`, and
/// description), ready to be placed in a frame.
struct C4ElementBox {
    enum Shape: Equatable {
        case box, rounded, octagon, database, queue
    }

    struct Line {
        var block: TextBlock
        /// Offset of the block's top from the frame's top.
        var top: Double
    }

    var shape: Shape
    var size: Size
    var lines: [Line]
    /// Offset of the person glyph's top from the frame's top, if drawn.
    var glyphTop: Double?
    var fill: Color
    var stroke: Color
    var text: Color

    static let capHeight = 10.0
    static let glyphSize = 44.0

    init(_ element: C4Diagram.Element, style: C4Diagram.ElementStyle, palette: C4Palette, measurer: any TextMeasurer) {
        let type = element.typeName
        shape = Self.shape(for: style.shape, form: element.form)
        fill = style.background ?? palette.background(for: type)
        stroke = style.border ?? palette.border(for: type)
        text = style.font ?? C4Palette.text(on: fill)

        let padding = palette.shapePadding
        let inset = shape == .queue ? padding + Self.capHeight : padding
        let limit = palette.wrap ? palette.shapeWidth - 2 * inset : nil
        func block(_ raw: String, _ font: Font) -> TextBlock {
            TextBlock(LabelParser.parse(raw), font: font, measurer: measurer, maxWidth: limit, forceWrap: limit != nil)
        }

        var y = padding * 0.6 + (shape == .database ? 2 * Self.capHeight : 0)
        var lines: [Line] = []
        var glyph: Double?
        func append(_ block: TextBlock, gap: Double) {
            guard !block.isEmpty else { return }
            if !lines.isEmpty || glyph != nil { y += gap }
            lines.append(Line(block: block, top: y))
            y += block.height
        }
        append(block("«\(type)»", palette.font(type, delta: -2, italic: true)), gap: 0)
        if element.category == .person, style.shape == nil || shape == .box {
            y += 4
            glyph = y
            y += Self.glyphSize
        }
        append(block(element.label, palette.font(type, delta: 2, bold: true)), gap: 6)
        if !element.technology.isEmpty {
            append(block("[\(element.technology)]", palette.font(type, delta: -2, italic: true)), gap: 2)
        }
        if !element.description.isEmpty {
            append(block(element.description, palette.font(type, delta: -1)), gap: 8)
        }
        y += padding * 0.6 + (shape == .database ? Self.capHeight : 0)
        self.lines = lines
        glyphTop = glyph
        let textWidth = lines.map(\.block.width).max() ?? 0
        size = Size(max(palette.shapeWidth, textWidth + 2 * inset), max(palette.shapeHeight, y))
    }

    /// Resolves a `$shape` keyword (C4-PlantUML and Structurizr names).
    static func shape(for keyword: String?, form: C4Diagram.Element.Form) -> Shape {
        switch keyword?.lowercased().replacingOccurrences(of: "()", with: "") {
        case "roundedboxshape", "rounded", "box": return .rounded
        case "eightsidedshape", "octagon": return .octagon
        case "cylinder", "database", "db": return .database
        case "queue", "pipe": return .queue
        default:
            switch form {
            case .box: return .box
            case .database: return .database
            case .queue: return .queue
            }
        }
    }

    // MARK: - Drawing

    /// The outline edges attach to.
    func outline(in frame: Rect) -> [Point] { body(in: frame).flattened() }

    func body(in r: Rect) -> Path {
        let c = Self.capHeight
        switch shape {
        case .box: return .rect(r, cornerRadius: 4)
        case .rounded: return .rect(r, cornerRadius: 14)
        case .octagon:
            let k = min(r.width, r.height) * 0.22
            return .polygon([Point(r.minX + k, r.minY), Point(r.maxX - k, r.minY), Point(r.maxX, r.minY + k),
                             Point(r.maxX, r.maxY - k), Point(r.maxX - k, r.maxY), Point(r.minX + k, r.maxY),
                             Point(r.minX, r.maxY - k), Point(r.minX, r.minY + k)])
        case .database:
            var path = Path()
            path.appendArc(center: Point(r.midX, r.minY + c), radiusX: r.width / 2, radiusY: c, from: 180, to: 360, connect: false)
            path.line(to: Point(r.maxX, r.maxY - c))
            path.appendArc(center: Point(r.midX, r.maxY - c), radiusX: r.width / 2, radiusY: c, from: 0, to: 180, connect: true)
            path.close()
            return path
        case .queue:
            var path = Path()
            path.move(to: Point(r.minX + c, r.minY))
            path.line(to: Point(r.maxX - c, r.minY))
            path.appendArc(center: Point(r.maxX - c, r.midY), radiusX: c, radiusY: r.height / 2, from: 270, to: 450, connect: true)
            path.line(to: Point(r.minX + c, r.maxY))
            path.appendArc(center: Point(r.minX + c, r.midY), radiusX: c, radiusY: r.height / 2, from: 90, to: 270, connect: true)
            path.close()
            return path
        }
    }

    /// The rim of a cylinder's top or a queue's front end.
    func rim(in r: Rect) -> Path? {
        let c = Self.capHeight
        var path = Path()
        switch shape {
        case .database:
            path.appendArc(center: Point(r.midX, r.minY + c), radiusX: r.width / 2, radiusY: c, from: 0, to: 180, connect: false)
        case .queue:
            path.appendArc(center: Point(r.maxX - c, r.midY), radiusX: c, radiusY: r.height / 2, from: 90, to: 270, connect: false)
        default: return nil
        }
        return path
    }

    func items(in frame: Rect, id: String) -> SceneItem {
        let stroke = Stroke(self.stroke, width: 1)
        var items: [SceneItem] = [.shape(ShapeItem(body(in: frame), fill: fill, stroke: stroke))]
        if let rim = rim(in: frame) { items.append(.shape(ShapeItem(rim, stroke: stroke))) }
        if let glyphTop { items.append(.shape(ShapeItem(Self.personGlyph(centerX: frame.midX, top: frame.minY + glyphTop), fill: text.withAlpha(0.9)))) }
        for line in lines {
            let box = Rect(x: frame.minX, y: frame.minY + line.top, width: frame.width, height: line.block.height)
            items.append(.text(TextItem(line.block, frame: box, alignment: .center, color: text)))
        }
        return .group(GroupItem(id: id, role: "c4-element", items: items))
    }

    /// A head-and-shoulders silhouette, the C4 person icon.
    static func personGlyph(centerX x: Double, top: Double) -> Path {
        let s = glyphSize
        var path = Path.circle(center: Point(x, top + s * 0.25), radius: s * 0.22)
        var body = Path()
        let w = s * 0.42, shoulder = top + s * 0.62, bottom = top + s
        body.move(to: Point(x - w, bottom))
        body.line(to: Point(x - w, shoulder + s * 0.1))
        body.curve(to: Point(x, top + s * 0.5), control1: Point(x - w, shoulder - s * 0.08), control2: Point(x - w * 0.55, top + s * 0.5))
        body.curve(to: Point(x + w, shoulder + s * 0.1), control1: Point(x + w * 0.55, top + s * 0.5), control2: Point(x + w, shoulder - s * 0.08))
        body.line(to: Point(x + w, bottom))
        body.close()
        path.append(body)
        return path
    }
}
