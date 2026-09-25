import Foundation

extension PieDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        PieSceneBuilder(diagram: self, context: context).build()
    }
}

/// One drawn slice: its share of the circle, in degrees clockwise from
/// twelve o'clock.
struct PieArc: Hashable, Sendable {
    var slice: PieDiagram.Slice
    /// Index of the slice in the diagram, which selects its color.
    var index: Int
    var startAngle: Double
    var endAngle: Double
    /// The slice's share of the total of every slice, 0...100.
    var percentage: Double

    var midAngle: Double { (startAngle + endAngle) / 2 }
}

extension PieDiagram {
    /// The slices mermaid.js draws, in clockwise order from twelve o'clock.
    ///
    /// Slices under 1% of the total are left out of the circle (they still
    /// appear in the legend) and the remaining slices share the full 360°.
    /// Percentages are relative to the total of every slice.
    var arcs: [PieArc] {
        let total = self.total
        guard total > 0 else { return [] }
        let drawn = slices.enumerated().filter { $0.element.value / total * 100 >= 1 }
        let drawnTotal = drawn.reduce(0) { $0 + $1.element.value }
        var angle = 0.0
        return drawn.map { index, slice in
            let sweep = slice.value / drawnTotal * 360
            defer { angle += sweep }
            return PieArc(slice: slice, index: index, startAngle: angle, endAngle: angle + sweep,
                          percentage: slice.value / total * 100)
        }
    }
}

struct PieSceneBuilder {
    let diagram: PieDiagram
    let context: RenderContext
    let config: ConfigValue
    var theme: Theme { context.theme }

    /// mermaid.js draws the pie in a fixed 450×450 frame.
    static let frameSize = 450.0
    static let margin = 40.0
    static let legendRectSize = 18.0
    static let legendSpacing = 4.0

    init(diagram: PieDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("pie")
    }

    enum LegendPosition: String { case top, bottom, left, right, center }

    /// Colors cycle through `pie1`...`pie12` by slice order.
    func color(ofSlice index: Int) -> Color {
        let colors = theme.pieColors.isEmpty ? [theme.primaryColor] : theme.pieColors
        return colors[index % colors.count]
    }

    /// Dark text on light themes; mermaid uses `taskTextDarkColor`.
    var darkTextColor: Color {
        if let color = theme.color("taskTextDarkColor") { return color }
        if theme.background.isDark { return Color(hex: 0xD3D3D3) }
        return theme.name == .base ? theme.textColor : .black
    }

    func build() -> Scene {
        let radius = Self.frameSize / 2 - Self.margin
        let textPosition = config["textPosition"]?.numberValue ?? 0.75
        let hole = config["donutHole"]?.numberValue ?? 0
        let innerRadius = hole > 0 && hole <= 0.9 ? hole * radius : 0
        let highlight = config["highlightSlice"]?.stringValue ?? ""
        let legendPosition = config["legendPosition"]?.stringValue.flatMap { LegendPosition(rawValue: $0.lowercased()) } ?? .right

        let outerStrokeWidth = context.themeNumber("pieOuterStrokeWidth", default: 2)
        let strokeWidth = context.themeNumber("pieStrokeWidth", default: 2)
        let opacity = context.themeNumber("pieOpacity", default: 0.7)
        let strokeColor = context.themeColor("pieStrokeColor", default: .black)

        // The pie is drawn around the origin, then everything is shifted.
        var pie: [SceneItem] = []
        pie.append(.shape(ShapeItem(.circle(center: .zero, radius: radius + outerStrokeWidth / 2),
                                    stroke: Stroke(context.themeColor("pieOuterStrokeColor", default: .black),
                                                   width: outerStrokeWidth))))
        let arcs = diagram.arcs
        for arc in arcs {
            let scale = !highlight.isEmpty && highlight == arc.slice.label ? 1.05 : 1
            let path = Self.sector(outer: radius * scale, inner: innerRadius * scale, from: arc.startAngle, to: arc.endAngle)
            pie.append(.group(GroupItem(id: arc.slice.label, role: "pieCircle", items: [
                .shape(ShapeItem(path, fill: color(ofSlice: arc.index),
                                 stroke: strokeWidth > 0 ? Stroke(strokeColor, width: strokeWidth) : nil,
                                 opacity: scale > 1 ? 1 : opacity)),
            ])))
        }
        let sectionSize = context.themeNumber("pieSectionTextSize", default: 17)
        let sectionColor = context.themeColor("pieSectionTextColor", default: theme.textColor)
        for arc in arcs {
            let block = context.label("\(Int(arc.percentage.rounded()))%", size: sectionSize)
            let centroid = Self.point(atAngle: arc.midAngle, radius: radius * textPosition)
            pie.append(.text(Self.baselineText(block, at: centroid, color: sectionColor)))
        }

        var items: [SceneItem] = []
        let legend = legendItems()
        var pieOffset = Point.zero
        let legendOffset: Point
        let rowHeight = Self.legendRectSize + Self.legendSpacing
        let legendHeight = rowHeight * Double(diagram.slices.count)
        let swatch = Self.legendRectSize + Self.legendSpacing
        switch legendPosition {
        case .center:
            legendOffset = Point(-legend.textWidth / 2 - swatch, -legendHeight / 2)
        case .top:
            legendOffset = Point(-legend.textWidth / 2 - swatch, -radius)
            pieOffset = Point(0, legendHeight + rowHeight)
        case .bottom:
            legendOffset = Point(-legend.textWidth / 2 - swatch, radius + rowHeight)
        case .left:
            legendOffset = Point(-radius - swatch, -legendHeight / 2)
            pieOffset = Point(legend.textWidth + swatch, 0)
        case .right:
            legendOffset = Point(12 * Self.legendRectSize, -legendHeight / 2)
        }
        items += pie.map { $0.offsetBy(dx: pieOffset.x, dy: pieOffset.y) }
        items += legend.items.map { $0.offsetBy(dx: legendOffset.x, dy: legendOffset.y) }

        // Frame: mermaid's 450-point square around the pie, grown to fit
        // the legend and title.
        let half = Self.frameSize / 2
        var frame = Rect(x: -half + pieOffset.x, y: -half + pieOffset.y, width: Self.frameSize, height: Self.frameSize)
        let title = diagram.title ?? context.title
        if let title, !title.isEmpty {
            let block = context.label(title, size: context.themeNumber("pieTitleTextSize", default: 25))
            let color = context.themeColor("pieTitleTextColor", default: darkTextColor)
            let text = Self.baselineText(block, at: Point(0, -(Self.frameSize - 50) / 2), color: color)
            items.append(.group(GroupItem(role: "pieTitleText", items: [.text(text)])))
        }
        if let content = items.compactMap(\.bounds).reduce(nil, { $0?.union($1) ?? $1 }) {
            frame = frame.union(content.insetBy(dx: -Self.margin / 2, dy: -Self.margin / 4))
        }
        let content = items.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        return DiagramCanvas(context: context, margin: 0, title: "").scene(content: content, size: frame.size)
    }

    /// Legend rows at the origin: an 18-point swatch per slice with its
    /// label (and value with `showData`) to the right.
    func legendItems() -> (items: [SceneItem], textWidth: Double) {
        let size = context.themeNumber("pieLegendTextSize", default: 17)
        let textColor = context.themeColor("pieLegendTextColor", default: darkTextColor)
        var items: [SceneItem] = []
        var textWidth = 0.0
        for (index, slice) in diagram.slices.enumerated() {
            let y = Double(index) * (Self.legendRectSize + Self.legendSpacing)
            let text = diagram.showData ? "\(slice.label) [\(ChartNumber.format(slice.value))]" : slice.label
            let block = context.text(RichText(plain: text), size: size)
            textWidth = max(textWidth, block.width)
            let swatch = Rect(x: 0, y: y, width: Self.legendRectSize, height: Self.legendRectSize)
            let fill = color(ofSlice: index)
            items.append(.group(GroupItem(role: "legend", items: [
                .shape(ShapeItem(.rect(swatch), fill: fill, stroke: Stroke(fill))),
                .text(Self.baselineText(block, at: Point(Self.legendRectSize + Self.legendSpacing,
                                                         y + Self.legendRectSize - Self.legendSpacing),
                                        color: textColor, anchor: .start)),
            ])))
        }
        return (items, textWidth)
    }

    // MARK: - Geometry

    /// A point at `angle` degrees clockwise from twelve o'clock.
    static func point(atAngle angle: Double, radius: Double) -> Point {
        let radians = (angle - 90) * .pi / 180
        return Point(radius * cos(radians), radius * sin(radians))
    }

    /// A pie slice (or ring segment when `inner` > 0) around the origin.
    static func sector(outer: Double, inner: Double, from start: Double, to end: Double) -> Path {
        var path = Path()
        if end - start >= 360 - 1e-9 {
            path.appendArc(center: .zero, radius: outer, from: -90, to: 270, connect: false)
            path.close()
            if inner > 0 {
                path.appendArc(center: .zero, radius: inner, from: 270, to: -90, connect: false)
                path.close()
            }
            return path
        }
        if inner > 0 {
            path.appendArc(center: .zero, radius: outer, from: start - 90, to: end - 90, connect: false)
            path.appendArc(center: .zero, radius: inner, from: end - 90, to: start - 90, connect: true)
        } else {
            path.move(to: .zero)
            path.appendArc(center: .zero, radius: outer, from: start - 90, to: end - 90, connect: true)
        }
        path.close()
        return path
    }

    /// Text whose alphabetic baseline sits at `point`, as SVG places a
    /// `<text>` without a dominant-baseline.
    static func baselineText(_ block: TextBlock, at point: Point, color: Color,
                             anchor: TextAnchor.Horizontal = .middle) -> TextItem {
        let baseline = block.lines.first?.baseline ?? block.height
        let top = point.y - baseline
        return TextItem(block, at: Point(point.x, top), anchor: TextAnchor(horizontal: anchor, vertical: .top), color: color)
    }
}
