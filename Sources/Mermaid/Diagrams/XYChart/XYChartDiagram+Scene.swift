import Foundation

extension XYChartDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        XYChartSceneBuilder(diagram: self, context: context).build()
    }
}

/// Lays out an XY chart like mermaid.js' chart orchestrator: the plot
/// first reserves `plotReservedSpacePercent` of the chart, then the
/// title, x-axis, y-axis and legend claim what they need from the rest,
/// and the plot grows into whatever is left.
struct XYChartSceneBuilder {
    let diagram: XYChartDiagram
    let context: RenderContext
    let config: ConfigValue
    let data: XYChartData

    init(diagram: XYChartDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("xyChart")
        data = XYChartData(diagram)
    }

    func setting(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }
    func flag(_ key: String, _ fallback: Bool) -> Bool { config[key]?.boolValue ?? fallback }

    var orientation: XYChartDiagram.Orientation {
        diagram.orientation ?? XYChartDiagram.Orientation(rawValue: config["chartOrientation"]?.stringValue ?? "") ?? .vertical
    }

    func color(_ key: String) -> Color {
        context.themeColor("xyChart", key, default: context.theme.primaryTextColor)
    }

    var palette: [Color] {
        let text = context.themeVariable("xyChart", "plotColorPalette")?.stringValue
            ?? XYChartDiagram.defaultPalette(for: context.theme.name)
        let colors = XYChartDiagram.palette(text)
        return colors.isEmpty ? XYChartDiagram.palette(XYChartDiagram.defaultPalette(for: .default)) : colors
    }

    var title: String? {
        let text = diagram.title ?? context.title
        return flag("showTitle", true) && text?.isEmpty == false ? text : nil
    }

    /// The finished geometry.
    struct Layout {
        var plot: Rect
        var xAxis: XYChartAxis
        var yAxis: XYChartAxis
        var titleFrame: Rect?
        var legendOrigin: Point
        var legendSize: Size
    }

    func makeAxes() -> (x: XYChartAxis, y: XYChartAxis) {
        let x = XYChartAxis(domain: data.x, settings: .init(config["xAxis"]),
                            colors: .init(title: color("xAxisTitleColor"), label: color("xAxisLabelColor"),
                                          tick: color("xAxisTickColor"), line: color("xAxisLineColor")),
                            title: diagram.xAxisTitle, context: context)
        let y = XYChartAxis(domain: .linear(data.y.0, data.y.1), settings: .init(config["yAxis"]),
                            colors: .init(title: color("yAxisTitleColor"), label: color("yAxisLabelColor"),
                                          tick: color("yAxisTickColor"), line: color("yAxisLineColor")),
                            title: diagram.yAxisTitle, context: context)
        return (x, y)
    }

    func layout() -> Layout {
        let width = setting("width", 700), height = setting("height", 500)
        let reserved = setting("plotReservedSpacePercent", 50)
        var available = Size(width, height)
        var chart = Size((width * reserved / 100).rounded(.down), (height * reserved / 100).rounded(.down))
        available.width -= chart.width
        available.height -= chart.height

        var titleHeight = 0.0
        if let title {
            let block = context.label(title, size: setting("titleFontSize", 20))
            titleHeight = block.height + 2 * setting("titlePadding", 10)
            if titleHeight > available.height { titleHeight = 0 }
        }
        available.height -= titleHeight

        var (xAxis, yAxis) = makeAxes()
        var plotOrigin: Point
        let legend = legendSize(available: Size(0, chart.height))
        var legendWidth = 0.0
        if orientation == .vertical {
            xAxis.position = .bottom
            available.height -= xAxis.claimSpace(available).height
            yAxis.position = .left
            let used = yAxis.claimSpace(available).width
            available.width -= used
            plotOrigin = Point(used, titleHeight)
        } else {
            xAxis.position = .left
            let used = xAxis.claimSpace(available).width
            available.width -= used
            yAxis.position = .top
            let topHeight = yAxis.claimSpace(available).height
            available.height -= topHeight
            plotOrigin = Point(used, titleHeight + topHeight)
        }
        if legend.width > 0, legend.width <= available.width, legend.height <= chart.height {
            legendWidth = legend.width
            available.width -= legendWidth
        }
        chart.width += max(available.width, 0)
        chart.height += max(available.height, 0)
        let plot = Rect(x: plotOrigin.x, y: plotOrigin.y, width: chart.width, height: chart.height)

        if orientation == .vertical {
            xAxis.setRange(plot.minX, plot.maxX)
            xAxis.bounds.origin = Point(plot.minX, plot.maxY)
            yAxis.setRange(plot.minY, plot.maxY)
            yAxis.bounds.origin = Point(0, plot.minY)
        } else {
            yAxis.setRange(plot.minX, plot.maxX)
            yAxis.bounds.origin = Point(plot.minX, titleHeight)
            xAxis.setRange(plot.minY, plot.maxY)
            xAxis.bounds.origin = Point(0, plot.minY)
        }
        if diagram.series.contains(where: { $0.kind == .bar }) { xAxis.makeRoomForBars() }
        let titleFrame = titleHeight > 0 ? Rect(x: 0, y: 0, width: width, height: titleHeight) : nil
        let legendOrigin = Point(plot.maxX, plot.minY + max((plot.height - legend.height) / 2, 0))
        return Layout(plot: plot, xAxis: xAxis, yAxis: yAxis, titleFrame: titleFrame,
                      legendOrigin: legendOrigin, legendSize: legendWidth > 0 ? legend : .zero)
    }

    func build() -> Scene {
        let layout = layout()
        let width = setting("width", 700), height = setting("height", 500)
        var items: [SceneItem] = []
        if let background = context.themeVariable("xyChart", "backgroundColor")?.stringValue.flatMap({ Color(css: $0) }) {
            items.append(.shape(ShapeItem(.rect(Rect(x: 0, y: 0, width: width, height: height)), fill: background)))
        }
        if let frame = layout.titleFrame, let title {
            let block = context.label(title, size: setting("titleFontSize", 20))
            items.append(.group(GroupItem(role: "chart-title", items: [
                .text(TextItem(block, at: frame.center, anchor: .center, color: color("titleColor"))),
            ])))
        }
        items += plotItems(layout)
        items += layout.xAxis.items() + layout.yAxis.items()
        items += legendItems(layout)

        var frame = Rect(x: 0, y: 0, width: width, height: height)
        if let content = items.compactMap(\.bounds).reduce(nil, { $0?.union($1) ?? $1 }) { frame = frame.union(content) }
        let shifted = items.map { $0.offsetBy(dx: -frame.minX, dy: -frame.minY) }
        return DiagramCanvas(context: context, margin: 0, title: "").scene(content: shifted, size: frame.size)
    }
}
