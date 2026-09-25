import Foundation

extension RadarDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        RadarSceneBuilder(diagram: self, context: context).build()
    }
}

/// Draws a radar chart like mermaid.js: a graticule of circles or
/// polygons, one axis per spoke starting at twelve o'clock and going
/// clockwise, translucent curves colored from the section scale, a legend
/// in the top-right corner and the title above.
struct RadarSceneBuilder {
    let diagram: RadarDiagram
    let context: RenderContext
    let config: ConfigValue

    init(diagram: RadarDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("radar")
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }
    func style(_ key: String, _ fallback: Double) -> Double { context.themeNumber("radar", key, default: fallback) }

    /// Curve `index`'s color, cycling through the section scale.
    func curveColor(_ index: Int) -> Color {
        let scale = context.theme.sectionColors
        return scale.isEmpty ? context.theme.primaryColor : scale[index % scale.count]
    }

    /// The angle of spoke `index` in radians, clockwise from twelve o'clock.
    func angle(_ index: Int) -> Double {
        2 * .pi * Double(index) / Double(max(diagram.axes.count, 1)) - .pi / 2
    }

    var radius: Double { min(setting("width", 600), setting("height", 600)) / 2 }

    /// The distance from the center for `value`, clamped to min...max.
    func distance(_ value: Double) -> Double {
        let lo = diagram.min, hi = diagram.resolvedMax
        guard hi > lo else { return 0 }
        return radius * (min(max(value, lo), hi) - lo) / (hi - lo)
    }

    func point(_ index: Int, _ distance: Double) -> Point {
        Point(distance * cos(angle(index)), distance * sin(angle(index)))
    }

    func build() -> Scene {
        var items: [SceneItem] = []
        items.append(.group(GroupItem(role: "graticule", items: graticule())))
        items.append(.group(GroupItem(role: "axes", items: axes())))
        items += curves()
        if diagram.showLegend { items.append(.group(GroupItem(role: "legend", items: legend()))) }

        let width = setting("width", 600), height = setting("height", 600)
        let top = setting("marginTop", 50), left = setting("marginLeft", 50)
        if let title = diagram.title ?? context.title, !title.isEmpty {
            let block = context.label(title, size: context.theme.fontSize)
            // mermaid.js hangs the title from the top margin, where a long
            // top axis label can collide with it; keep it clear of the chart.
            let contentTop = items.compactMap(\.bounds).map(\.minY).min() ?? 0
            let y = min(-height / 2 - top, contentTop - block.height - 6)
            items.append(.text(TextItem(block, at: Point(0, y), anchor: .topCenter, color: context.theme.titleColor)))
        }
        // The chart is drawn around the origin; the frame is mermaid's
        // margins around width × height, grown to fit overflowing labels.
        var frame = Rect(x: -width / 2 - left, y: -height / 2 - top,
                         width: width + left + setting("marginRight", 50),
                         height: height + top + setting("marginBottom", 50))
        if let content = items.compactMap(\.bounds).reduce(nil, { $0?.union($1) ?? $1 }) { frame = frame.union(content) }
        let shifted = items.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        return DiagramCanvas(context: context, margin: 0, title: "").scene(content: shifted, size: frame.size)
    }

    func graticule() -> [SceneItem] {
        let color = context.themeColor("radar", "graticuleColor", default: Color(hex: 0xDEDEDE))
        let fill = color.withAlpha(color.alpha * style("graticuleOpacity", 0.3))
        let stroke = Stroke(color, width: style("graticuleStrokeWidth", 1))
        let ticks = max(diagram.ticks, 1)
        return (1...ticks).map { tick in
            let r = radius * Double(tick) / Double(ticks)
            let path: Path
            switch diagram.graticule {
            case .circle: path = .circle(center: .zero, radius: r)
            case .polygon: path = .polygon(diagram.axes.indices.map { point($0, r) })
            }
            return .shape(ShapeItem(path, fill: fill, stroke: stroke))
        }
    }

    func axes() -> [SceneItem] {
        let color = context.themeColor("radar", "axisColor", default: context.theme.lineColor)
        let stroke = Stroke(color, width: style("axisStrokeWidth", 2))
        let scale = setting("axisScaleFactor", 1), labelFactor = setting("axisLabelFactor", 1.05)
        let fontSize = style("axisLabelFontSize", 12)
        var lines: [SceneItem] = [], labels: [SceneItem] = []
        for (index, axis) in diagram.axes.enumerated() {
            let cosA = cos(angle(index)), sinA = sin(angle(index))
            lines.append(.shape(ShapeItem(.polyline([.zero, point(index, radius * scale)]), stroke: stroke)))
            // Labels extend away from the center: anchored by which side of
            // the chart they sit on, pushed 4 points past the label radius.
            let horizontal: TextAnchor.Horizontal = cosA > 0.01 ? .start : cosA < -0.01 ? .end : .middle
            let vertical: TextAnchor.Vertical = sinA > 0.01 ? .top : sinA < -0.01 ? .bottom : .middle
            let block = context.label(axis.label, size: fontSize)
            let at = point(index, radius * labelFactor + 4)
            labels.append(.text(TextItem(block, at: at, anchor: TextAnchor(horizontal: horizontal, vertical: vertical),
                                         color: context.theme.textColor)))
        }
        return lines + labels
    }

    func curves() -> [SceneItem] {
        let opacity = style("curveOpacity", 0.5)
        let strokeWidth = style("curveStrokeWidth", 2)
        let tension = setting("curveTension", 0.17)
        return diagram.curves.enumerated().compactMap { index, curve in
            // Curves without exactly one value per axis are skipped, as in mermaid.js.
            guard curve.values.count == diagram.axes.count, !curve.values.isEmpty else { return nil }
            let points = curve.values.enumerated().map { point($0, distance($1)) }
            let path = diagram.graticule == .circle ? Self.closedCurve(through: points, tension: tension) : .polygon(points)
            let color = curveColor(index)
            return .group(GroupItem(id: curve.id, role: "radarCurve", items: [
                .shape(ShapeItem(path, fill: color.withAlpha(color.alpha * opacity),
                                 stroke: strokeWidth > 0 ? Stroke(color, width: strokeWidth, join: .round) : nil)),
            ]))
        }
    }

    func legend() -> [SceneItem] {
        let width = setting("width", 600), height = setting("height", 600)
        let x = (width / 2 + setting("marginRight", 50)) * 3 / 4
        let y = -(height / 2 + setting("marginTop", 50)) * 3 / 4
        let box = style("legendBoxSize", 12), fontSize = style("legendFontSize", 12)
        let opacity = style("curveOpacity", 0.5)
        let lineHeight = max(20, box + 8, fontSize * 1.25 + 4)
        return diagram.curves.enumerated().flatMap { index, curve -> [SceneItem] in
            let top = y + Double(index) * lineHeight
            let color = curveColor(index)
            let block = context.label(curve.label, size: fontSize)
            return [
                .shape(ShapeItem(.rect(Rect(x: x, y: top, width: box, height: box)),
                                 fill: color.withAlpha(color.alpha * opacity), stroke: Stroke(color))),
                .text(TextItem(block, at: Point(x + box + 4, top + box / 2), anchor: .leading, color: context.theme.textColor)),
            ]
        }
    }

    /// A closed Catmull-Rom style spline through `points`, with control
    /// points `tension` of the way toward the neighbours (mermaid.js'
    /// `closedRoundCurve`).
    static func closedCurve(through points: [Point], tension: Double) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let n = points.count
        for i in 0..<n {
            let p0 = points[(i - 1 + n) % n], p1 = points[i], p2 = points[(i + 1) % n], p3 = points[(i + 2) % n]
            path.curve(to: p2, control1: p1 + (p2 - p0) * tension, control2: p2 - (p3 - p1) * tension)
        }
        path.close()
        return path
    }
}
