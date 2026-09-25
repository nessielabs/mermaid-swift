import Foundation

/// One XY chart axis, ported from mermaid.js' `BaseAxis`, `BandAxis` and
/// `LinearAxis`: it claims space for its line, tick labels, ticks and
/// title (dropping whatever does not fit), maps data onto its range, and
/// draws itself on the left, bottom or top of the plot.
struct XYChartAxis {
    enum Position { case left, bottom, top }

    /// `xyChart.xAxis` / `xyChart.yAxis` settings.
    struct Settings {
        var showLabel = true, labelFontSize = 14.0, labelPadding = 5.0
        var showTitle = true, titleFontSize = 16.0, titlePadding = 5.0
        var showTick = true, tickLength = 5.0, tickWidth = 2.0
        var showAxisLine = true, axisLineWidth = 2.0
        var labelRotation = 0.0

        init(_ config: ConfigValue?) {
            func number(_ key: String, _ value: inout Double) { if let v = config?[key]?.numberValue { value = v } }
            func flag(_ key: String, _ value: inout Bool) { if let v = config?[key]?.boolValue { value = v } }
            flag("showLabel", &showLabel); number("labelFontSize", &labelFontSize); number("labelPadding", &labelPadding)
            flag("showTitle", &showTitle); number("titleFontSize", &titleFontSize); number("titlePadding", &titlePadding)
            flag("showTick", &showTick); number("tickLength", &tickLength); number("tickWidth", &tickWidth)
            flag("showAxisLine", &showAxisLine); number("axisLineWidth", &axisLineWidth)
            number("labelRotation", &labelRotation)
        }
    }

    struct Colors {
        var title: Color, label: Color, tick: Color, line: Color
    }

    let domain: XYChartData.XDomain
    let settings: Settings
    let colors: Colors
    let title: String?
    let context: RenderContext

    var position = Position.left
    var range = (0.0, 10.0)
    var bounds = Rect(x: 0, y: 0, width: 0, height: 0)
    var outerPadding = 0.0
    var showsTitle = false, showsLabels = false, showsTicks = false, showsLine = false
    var titleHeight = 0.0

    init(domain: XYChartData.XDomain, settings: Settings, colors: Colors, title: String?, context: RenderContext) {
        self.domain = domain
        self.settings = settings
        self.colors = colors
        self.title = title?.isEmpty == false ? title : nil
        self.context = context
    }

    /// Label rotation in radians; only the bottom axis rotates labels and
    /// only within ±90°.
    var rotation: Double {
        (-90...90).contains(settings.labelRotation) ? settings.labelRotation * .pi / 180 : 0
    }

    // MARK: - Scale

    /// The drawing range inside the outer padding.
    var innerRange: (Double, Double) { (range.0 + outerPadding, range.1 - outerPadding) }

    var tickValues: [Double] {
        switch domain {
        case .categories(let names): return names.indices.map(Double.init)
        case .linear(let a, let b): return ChartTicks.ticks(a, b)
        }
    }

    func tickLabel(_ value: Double) -> String {
        switch domain {
        case .categories(let names): return names.indices.contains(Int(value)) ? names[Int(value)] : ""
        case .linear: return ChartNumber.format(value)
        }
    }

    /// The pixel coordinate of a category index or value along the axis.
    func position(of value: Double) -> Double {
        let (r0, r1) = innerRange
        switch domain {
        case .categories(let names):
            // d3.scaleBand with paddingInner 1: points spread end to end.
            guard names.count > 1 else { return (r0 + r1) / 2 }
            return r0 + value * (r1 - r0) / Double(names.count - 1)
        case .linear(let a, let b):
            // A left axis grows upward, so its domain is reversed.
            let scale = LinearScale(domain: position == .left ? (b, a) : (a, b), range: (r0, r1))
            return scale(value)
        }
    }

    var tickDistance: Double {
        let (r0, r1) = innerRange
        return abs(r1 - r0) / Double(max(tickValues.count, 1))
    }

    /// Width and height of the widest and tallest tick label.
    func labelDimension() -> Size {
        let blocks = tickValues.map { context.text(RichText(plain: tickLabel($0)), size: settings.labelFontSize) }
        return Size(blocks.map(\.width).max() ?? 0, blocks.map(\.height).max() ?? 0)
    }

    func titleBlock() -> TextBlock? {
        title.map { context.label($0, size: settings.titleFontSize) }
    }

    /// Widens the outer padding so bars centered on the first and last
    /// categories are not cut off.
    mutating func makeRoomForBars() {
        if 0.7 * tickDistance > outerPadding * 2 {
            outerPadding = (0.7 * tickDistance / 2).rounded(.down)
        }
    }

    // MARK: - Space

    /// Claims space within `available` and returns the size used.
    mutating func claimSpace(_ available: Size) -> Size {
        showsTitle = false; showsLabels = false; showsTicks = false; showsLine = false
        if position == .left {
            var width = available.width
            if settings.showAxisLine, width > settings.axisLineWidth { width -= settings.axisLineWidth; showsLine = true }
            if settings.showLabel {
                let label = labelDimension()
                outerPadding = min(label.height / 2, 0.2 * available.height)
                let needed = label.width + settings.labelPadding * 2
                if needed <= width { width -= needed; showsLabels = true }
            }
            if settings.showTick, width >= settings.tickLength { showsTicks = true; width -= settings.tickLength }
            if settings.showTitle, let block = titleBlock() {
                let needed = block.height + settings.titlePadding * 2
                titleHeight = block.height
                if needed <= width { width -= needed; showsTitle = true }
            }
            bounds.size = Size(available.width - width, available.height)
        } else {
            var height = available.height
            if settings.showAxisLine, height > settings.axisLineWidth { height -= settings.axisLineWidth; showsLine = true }
            if settings.showLabel {
                let label = labelDimension()
                outerPadding = min(label.width / 2, 0.2 * available.width)
                var needed = label.height
                if position == .bottom, rotation != 0 {
                    needed = max(needed, abs(sin(rotation) * label.width) + abs(cos(rotation) * label.height))
                }
                needed += settings.labelPadding * 2
                if needed <= height { height -= needed; showsLabels = true }
            }
            if settings.showTick, height >= settings.tickLength { showsTicks = true; height -= settings.tickLength }
            if settings.showTitle, let block = titleBlock() {
                let needed = block.height + settings.titlePadding * 2
                titleHeight = block.height
                if needed <= height { height -= needed; showsTitle = true }
            }
            bounds.size = Size(available.width, available.height - height)
        }
        return bounds.size
    }

    /// Sets the pixel range along the axis; the axis' extent follows it.
    mutating func setRange(_ start: Double, _ end: Double) {
        range = (start, end)
        if position == .left { bounds.size.height = end - start } else { bounds.size.width = end - start }
    }

    // MARK: - Drawing

    func items() -> [SceneItem] {
        var line: [SceneItem] = [], labels: [SceneItem] = [], ticks: [SceneItem] = [], titles: [SceneItem] = []
        let s = settings
        let b = bounds
        let lineInset = showsLine ? s.axisLineWidth : 0
        let tickInset = showsTicks ? s.tickLength : 0
        func segment(_ a: Point, _ z: Point, _ color: Color, _ width: Double) -> SceneItem {
            .shape(ShapeItem(.polyline([a, z]), stroke: Stroke(color, width: width)))
        }
        func label(_ value: Double) -> TextBlock {
            context.text(RichText(plain: tickLabel(value)), size: s.labelFontSize)
        }
        switch position {
        case .left:
            if showsLine {
                let x = b.maxX - s.axisLineWidth / 2
                line.append(segment(Point(x, b.minY), Point(x, b.maxY), colors.line, s.axisLineWidth))
            }
            for value in tickValues {
                let y = position(of: value)
                if showsLabels {
                    let x = b.maxX - s.labelPadding - tickInset - lineInset
                    labels.append(.text(TextItem(label(value), at: Point(x, y), anchor: .trailing, color: colors.label)))
                }
                if showsTicks {
                    let x = b.maxX - lineInset
                    ticks.append(segment(Point(x, y), Point(x - s.tickLength, y), colors.tick, s.tickWidth))
                }
            }
            if showsTitle, let block = titleBlock() {
                titles.append(.text(TextItem(block, at: Point(b.minX + s.titlePadding, b.midY), anchor: .topCenter,
                                             color: colors.title, rotation: 270)))
            }
        case .bottom:
            if showsLine {
                let y = b.minY + s.axisLineWidth / 2
                line.append(segment(Point(b.minX, y), Point(b.maxX, y), colors.line, s.axisLineWidth))
            }
            let dimension = rotation == 0 ? Size.zero : labelDimension()
            for value in tickValues {
                let x = position(of: value)
                if showsLabels {
                    let block = label(value)
                    let point = Point(x + sin(rotation) * dimension.height / 2,
                                      b.minY + s.labelPadding + tickInset + lineInset + abs(sin(rotation) * dimension.width / 2))
                    labels.append(.text(TextItem(block, at: point, anchor: .topCenter, color: colors.label,
                                                 rotation: rotation * 180 / .pi)))
                }
                if showsTicks {
                    let y = b.minY + lineInset
                    ticks.append(segment(Point(x, y), Point(x, y + s.tickLength), colors.tick, s.tickWidth))
                }
            }
            if showsTitle, let block = titleBlock() {
                let point = Point((range.0 + range.1) / 2, b.maxY - s.titlePadding - titleHeight)
                titles.append(.text(TextItem(block, at: point, anchor: .topCenter, color: colors.title)))
            }
        case .top:
            if showsLine {
                let y = b.maxY - s.axisLineWidth / 2
                line.append(segment(Point(b.minX, y), Point(b.maxX, y), colors.line, s.axisLineWidth))
            }
            for value in tickValues {
                let x = position(of: value)
                if showsLabels {
                    let y = b.minY + (showsTitle ? titleHeight + s.titlePadding * 2 : 0) + s.labelPadding
                    labels.append(.text(TextItem(label(value), at: Point(x, y), anchor: .topCenter, color: colors.label)))
                }
                if showsTicks {
                    let y = b.maxY - lineInset
                    ticks.append(segment(Point(x, y), Point(x, y - s.tickLength), colors.tick, s.tickWidth))
                }
            }
            if showsTitle, let block = titleBlock() {
                titles.append(.text(TextItem(block, at: Point(b.midX, b.minY + s.titlePadding), anchor: .topCenter,
                                             color: colors.title)))
            }
        }
        let name = position == .left ? "left-axis" : position == .bottom ? "bottom-axis" : "top-axis"
        return [.group(GroupItem(role: name, items: line + labels + ticks + titles))]
    }
}
