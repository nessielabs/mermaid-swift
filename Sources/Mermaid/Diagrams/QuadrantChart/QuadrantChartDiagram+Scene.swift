import Foundation

extension QuadrantChartDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        QuadrantChartSceneBuilder(diagram: self, context: context).build()
    }
}

/// Lays out a quadrant chart with mermaid.js' `QuadrantBuilder` geometry:
/// a fixed chart box, the title band on top, an x-axis label band at the
/// top (or at the bottom whenever there are points), a rotated y-axis
/// label band on the left or right, and the four quadrants filling the
/// rest.
struct QuadrantChartSceneBuilder {
    let diagram: QuadrantChartDiagram
    let context: RenderContext
    let config: ConfigValue

    init(diagram: QuadrantChartDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("quadrantChart")
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    /// The quadrant area and label bands, in chart coordinates.
    struct Space {
        var titleHeight: Double
        var xAxisTop: Double
        var xAxisBottom: Double
        var yAxisLeft: Double
        var yAxisRight: Double
        var quadrants: Rect
    }

    var title: String? {
        let text = diagram.title ?? context.title
        return text?.isEmpty == false ? text : nil
    }

    var showsXAxis: Bool { diagram.xAxisLeft != nil || diagram.xAxisRight != nil }
    var showsYAxis: Bool { diagram.yAxisBottom != nil || diagram.yAxisTop != nil }
    /// mermaid.js moves the x-axis labels below the chart once there are
    /// points, so they never collide with quadrant labels.
    var xAxisAtTop: Bool { diagram.points.isEmpty && (config["xAxisPosition"]?.stringValue ?? "top") == "top" }
    var yAxisAtLeft: Bool { (config["yAxisPosition"]?.stringValue ?? "left") != "right" }

    func space() -> Space {
        let width = setting("chartWidth", 500), height = setting("chartHeight", 500)
        let padding = setting("quadrantPadding", 5)
        let xBand = showsXAxis ? setting("xAxisLabelPadding", 5) * 2 + setting("xAxisLabelFontSize", 16) : 0
        let yBand = showsYAxis ? setting("yAxisLabelPadding", 5) * 2 + setting("yAxisLabelFontSize", 16) : 0
        let titleHeight = title == nil ? 0 : setting("titleFontSize", 20) + setting("titlePadding", 10) * 2
        let top = xAxisAtTop ? xBand : 0, bottom = xAxisAtTop ? 0 : xBand
        let left = yAxisAtLeft ? yBand : 0, right = yAxisAtLeft ? 0 : yBand
        let quadrants = Rect(x: padding + left, y: padding + top + titleHeight,
                             width: max(0, width - padding * 2 - left - right),
                             height: max(0, height - padding * 2 - top - bottom - titleHeight))
        return Space(titleHeight: titleHeight, xAxisTop: top, xAxisBottom: bottom, yAxisLeft: left,
                     yAxisRight: right, quadrants: quadrants)
    }

    // MARK: - Colors

    /// khroma's rgb `adjust`, which mermaid uses to shade the quadrants.
    static func shifted(_ color: Color, by amount: Double) -> Color {
        Color(red: color.red + amount / 255, green: color.green + amount / 255, blue: color.blue + amount / 255,
              alpha: color.alpha)
    }

    func quadrantFill(_ index: Int) -> Color {
        let primary = context.theme.primaryColor
        return context.themeColor("quadrant\(index + 1)Fill", default: Self.shifted(primary, by: Double(index) * 5))
    }

    func quadrantTextFill(_ index: Int) -> Color {
        let text = context.theme.primaryTextColor
        return context.themeColor("quadrant\(index + 1)TextFill", default: Self.shifted(text, by: -Double(index) * 5))
    }

    var pointFill: Color {
        let base = quadrantFill(0)
        return context.themeColor("quadrantPointFill", default: base.isDark ? base.lightened(30) : base.darkened(35))
    }

    // MARK: - Scene

    func text(_ raw: String, size: Double, maxWidth: Double? = nil) -> TextBlock {
        context.label(raw, size: size, maxWidth: maxWidth)
    }

    func build() -> Scene {
        let space = space()
        let q = space.quadrants
        let halfWidth = q.width / 2, halfHeight = q.height / 2
        let theme = context.theme
        var items: [SceneItem] = []

        // Quadrants 1 (top right), 2 (top left), 3 (bottom left), 4 (bottom right).
        let origins = [Point(q.minX + halfWidth, q.minY), Point(q.minX, q.minY),
                       Point(q.minX, q.minY + halfHeight), Point(q.minX + halfWidth, q.minY + halfHeight)]
        let labelSize = setting("quadrantLabelFontSize", 16)
        for (index, origin) in origins.enumerated() {
            let rect = Rect(x: origin.x, y: origin.y, width: halfWidth, height: halfHeight)
            var group: [SceneItem] = [.shape(ShapeItem(.rect(rect), fill: quadrantFill(index)))]
            if let label = diagram.quadrantLabels[index], !label.isEmpty {
                let block = text(label, size: labelSize, maxWidth: halfWidth)
                let placed = diagram.points.isEmpty
                    ? TextItem(block, at: rect.center, anchor: .center, color: quadrantTextFill(index))
                    : TextItem(block, at: Point(rect.midX, rect.minY + setting("quadrantTextTopPadding", 5)),
                               anchor: .topCenter, color: quadrantTextFill(index))
                group.append(.text(placed))
            }
            items.append(.group(GroupItem(id: "quadrant-\(index + 1)", role: "quadrant", items: group)))
        }
        items.append(.group(GroupItem(role: "border", items: borders(q))))
        items.append(.group(GroupItem(role: "data-points", items: points(q))))
        items.append(.group(GroupItem(role: "labels", items: axisLabels(space))))
        if let title {
            let block = text(title, size: setting("titleFontSize", 20))
            let placed = TextItem(block, at: Point(setting("chartWidth", 500) / 2, setting("titlePadding", 10)),
                                  anchor: .topCenter, color: context.themeColor("quadrantTitleFill", default: theme.primaryTextColor))
            items.append(.group(GroupItem(role: "title", items: [.text(placed)])))
        }

        var frame = Rect(x: 0, y: 0, width: setting("chartWidth", 500), height: setting("chartHeight", 500))
        if let content = items.compactMap(\.bounds).reduce(nil, { $0?.union($1) ?? $1 }) { frame = frame.union(content) }
        let shifted = items.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        return DiagramCanvas(context: context, margin: 0, title: "").scene(content: shifted, size: frame.size)
    }

    func borders(_ q: Rect) -> [SceneItem] {
        let external = setting("quadrantExternalBorderStrokeWidth", 2)
        let internalWidth = setting("quadrantInternalBorderStrokeWidth", 1)
        let externalColor = context.themeColor("quadrantExternalBorderStrokeFill", default: context.theme.primaryBorderColor)
        let internalColor = context.themeColor("quadrantInternalBorderStrokeFill", default: context.theme.primaryBorderColor)
        let half = external / 2
        func line(_ a: Point, _ b: Point, _ color: Color, _ width: Double) -> SceneItem {
            .shape(ShapeItem(.polyline([a, b]), stroke: Stroke(color, width: width)))
        }
        return [
            line(Point(q.minX - half, q.minY), Point(q.maxX + half, q.minY), externalColor, external),
            line(Point(q.maxX, q.minY + half), Point(q.maxX, q.maxY - half), externalColor, external),
            line(Point(q.minX - half, q.maxY), Point(q.maxX + half, q.maxY), externalColor, external),
            line(Point(q.minX, q.minY + half), Point(q.minX, q.maxY - half), externalColor, external),
            line(Point(q.midX, q.minY + half), Point(q.midX, q.maxY - half), internalColor, internalWidth),
            line(Point(q.minX + half, q.midY), Point(q.maxX - half, q.midY), internalColor, internalWidth),
        ]
    }

    /// Points are drawn last-declared first, so the first point declared
    /// ends up on top, as in mermaid.js. Labels are drawn after every
    /// point so a large point never hides another point's label.
    func points(_ q: Rect) -> [SceneItem] {
        let defaultRadius = setting("pointRadius", 5)
        let textPadding = setting("pointTextPadding", 5)
        let textSize = setting("pointLabelFontSize", 12)
        let textColor = context.themeColor("quadrantPointTextFill", default: context.theme.primaryTextColor)
        var circles: [SceneItem] = [], labels: [SceneItem] = []
        for point in diagram.points.reversed() {
            let style = diagram.resolvedStyle(of: point)
            let center = Point(q.minX + point.x * q.width, q.maxY - point.y * q.height)
            let radius = style.radius ?? defaultRadius
            let strokeWidth = style.strokeWidth ?? 0
            let stroke = strokeWidth > 0 ? Stroke(style.strokeColor ?? pointFill, width: strokeWidth) : nil
            circles.append(.shape(ShapeItem(.circle(center: center, radius: radius), fill: style.color ?? pointFill,
                                            stroke: stroke)))
            // mermaid.js hangs the label pointTextPadding below the center,
            // which clears only the default radius; larger points push their
            // label down so it never sits on the point.
            let labelTop = center.y + textPadding + max(0, radius - defaultRadius) + (stroke == nil ? 0 : strokeWidth / 2)
            let block = text(point.label, size: textSize, maxWidth: q.width / 2)
            labels.append(.text(TextItem(block, at: Point(center.x, labelTop), anchor: .topCenter, color: textColor)))
        }
        return circles + labels
    }

    func axisLabels(_ space: Space) -> [SceneItem] {
        let q = space.quadrants
        var items: [SceneItem] = []
        let padding = setting("quadrantPadding", 5)
        if showsXAxis {
            let size = setting("xAxisLabelFontSize", 16), labelPadding = setting("xAxisLabelPadding", 5)
            let color = context.themeColor("quadrantXAxisTextFill", default: context.theme.primaryTextColor)
            let centered = diagram.xAxisRight != nil
            let y = xAxisAtTop ? labelPadding + space.titleHeight : labelPadding + q.maxY + padding
            for (index, label) in [diagram.xAxisLeft, diagram.xAxisRight].enumerated() {
                guard let label else { continue }
                let x = q.minX + Double(index) * q.width / 2 + (centered ? q.width / 4 : 0)
                let anchor = TextAnchor(horizontal: centered ? .middle : .start, vertical: .top)
                items.append(.text(TextItem(text(label, size: size, maxWidth: q.width / 2), at: Point(x, y),
                                            anchor: anchor, color: color)))
            }
        }
        if showsYAxis {
            let size = setting("yAxisLabelFontSize", 16), labelPadding = setting("yAxisLabelPadding", 5)
            let color = context.themeColor("quadrantYAxisTextFill", default: context.theme.primaryTextColor)
            let centered = diagram.yAxisTop != nil
            let x = yAxisAtLeft ? labelPadding : labelPadding + q.maxX + padding
            for (index, label) in [diagram.yAxisBottom, diagram.yAxisTop].enumerated() {
                guard let label else { continue }
                let y = q.maxY - Double(index) * q.height / 2 - (centered ? q.height / 4 : 0)
                let anchor = TextAnchor(horizontal: centered ? .middle : .start, vertical: .top)
                items.append(.text(TextItem(text(label, size: size, maxWidth: q.height / 2), at: Point(x, y),
                                            anchor: anchor, color: color, rotation: -90)))
            }
        }
        return items
    }
}
