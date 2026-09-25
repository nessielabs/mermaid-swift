import Foundation

/// Bars, lines, data labels and the legend of an XY chart.
extension XYChartSceneBuilder {
    func plotColor(_ index: Int) -> Color {
        let colors = palette
        return colors[index % colors.count]
    }

    /// The color for thin marks (lines, point labels, line legend markers).
    /// mermaid.js' default palettes start with near-background colors such
    /// as #ECECFF, which are fine as bar fills but make a 2-point line
    /// invisible; such colors are darkened (or lightened on dark
    /// backgrounds) until they reach a 2:1 contrast with the background.
    func strokeColor(_ index: Int) -> Color {
        let background = context.themeColor("xyChart", "backgroundColor", default: context.theme.background)
        var color = plotColor(index)
        func contrast(_ a: Color, _ b: Color) -> Double {
            let (hi, lo) = (max(a.luminance, b.luminance), min(a.luminance, b.luminance))
            return (hi + 0.05) / (lo + 0.05)
        }
        var steps = 0
        while contrast(color, background) < 2, steps < 20 {
            color = background.isDark ? color.lightened(5) : color.darkened(5)
            steps += 1
        }
        return color
    }

    /// Where a data point lands: x along the category axis, y along the
    /// value axis, swapped for horizontal charts.
    func point(_ x: Double, _ y: Double, _ layout: Layout) -> Point {
        let along = layout.xAxis.position(of: x), value = layout.yAxis.position(of: y)
        return orientation == .vertical ? Point(along, value) : Point(value, along)
    }

    func plotItems(_ layout: Layout) -> [SceneItem] {
        var items: [SceneItem] = []
        for (index, plot) in data.plots.enumerated() {
            switch plot.series.kind {
            case .line: items.append(lineItems(plot, color: strokeColor(index), index: index, layout))
            case .bar: items.append(barItems(plot, color: plotColor(index), index: index, layout))
            }
        }
        return items
    }

    func lineItems(_ plot: XYChartData.Plot, color: Color, index: Int, _ layout: Layout) -> SceneItem {
        let points = plot.points.filter { $0.y.isFinite }.map { point($0.x, $0.y, layout) }
        var items: [SceneItem] = []
        if points.count > 1 {
            items.append(.shape(ShapeItem(.polyline(points), stroke: Stroke(color, width: 2, join: .round))))
        } else if let single = points.first {
            items.append(.shape(ShapeItem(.circle(center: single, radius: 2), fill: color)))
        }
        for (entry, position) in zip(plot.points.filter { $0.y.isFinite }, points) {
            guard let label = entry.label, !label.isEmpty else { continue }
            let block = context.text(RichText(plain: label), size: 12)
            let placed = orientation == .vertical
                ? TextItem(block, at: Point(position.x, position.y - 10), anchor: .center, color: color)
                : TextItem(block, at: Point(position.x + 10, position.y), anchor: .leading, color: color)
            items.append(.text(placed))
        }
        return .group(GroupItem(id: "line-plot-\(index)", role: "line-plot", items: items))
    }

    /// Bars grow from zero (clamped into the value domain); mermaid.js
    /// grows them from the plot edge, which draws negative values upside
    /// down.
    func barItems(_ plot: XYChartData.Plot, color: Color, index: Int, _ layout: Layout) -> SceneItem {
        let barWidth = min(layout.xAxis.outerPadding * 2, layout.xAxis.tickDistance) * 0.95
        let (lo, hi) = (min(data.y.0, data.y.1), max(data.y.0, data.y.1))
        let baseline = layout.yAxis.position(of: min(max(0, lo), hi))
        var bars: [(rect: Rect, value: Double)] = []
        for entry in plot.points where entry.y.isFinite {
            let along = layout.xAxis.position(of: entry.x), value = layout.yAxis.position(of: entry.y)
            let rect = orientation == .vertical
                ? Rect(x: along - barWidth / 2, y: min(value, baseline), width: barWidth, height: abs(baseline - value))
                : Rect(x: min(value, baseline), y: along - barWidth / 2, width: abs(value - baseline), height: barWidth)
            bars.append((rect, entry.y))
        }
        var items: [SceneItem] = bars.map { .shape(ShapeItem(.rect($0.rect), fill: color)) }
        if flag("showDataLabel", false) { items += dataLabels(bars, plot: layout.plot) }
        return .group(GroupItem(id: "bar-plot-\(index)", role: "bar-plot", items: items))
    }

    /// Value labels in (or just outside) each bar, at one font size that
    /// fits every bar, as mermaid.js sizes them.
    /// Labels placed outside a bar that would leave the plot (the tallest
    /// bars of an auto-ranged chart) go inside that bar instead.
    func dataLabels(_ bars: [(rect: Rect, value: Double)], plot: Rect) -> [SceneItem] {
        let outside = flag("showDataLabelOutsideBar", false)
        let visible = bars.filter { $0.rect.width > 0 && $0.rect.height > 0 }
        let texts = visible.map { ChartNumber.format($0.value) }
        let unit = Font(family: context.theme.fontFamily, size: 100)
        let widthPerPoint = texts.map { context.measurer.width(of: $0, font: unit) / 100 }
        let offset = 10.0
        var sizes: [Double] = []
        for (bar, perPoint) in zip(visible, widthPerPoint) where perPoint > 0 {
            if orientation == .vertical {
                var size = bar.rect.width / perPoint
                if !outside { size = min(size, bar.rect.height - offset) }
                sizes.append(size)
            } else {
                var size = bar.rect.height * 0.7
                if !outside { size = min(size, (bar.rect.width - offset) / perPoint) }
                sizes.append(size)
            }
        }
        // One size for every bar; capped so wide bars do not get poster type.
        guard let fitted = sizes.min(), fitted.rounded(.down) >= 6 else { return [] }
        let size = min(fitted.rounded(.down), 18)
        let labelColor = color("dataLabelColor")
        return zip(visible, texts).map { bar, text in
            let block = context.text(RichText(plain: text), size: size)
            let r = bar.rect
            let placed: TextItem
            if orientation == .vertical {
                // A negative bar hangs below the baseline; label its far end.
                let down = bar.value < 0
                let fitsOutside = down ? r.maxY + offset + block.height <= plot.maxY : r.minY - offset - block.height >= plot.minY
                let out = outside && fitsOutside
                let y = out ? (down ? r.maxY + offset : r.minY - offset) : (down ? r.maxY - offset : r.minY + offset)
                let vertical: TextAnchor.Vertical = out == down ? .top : .bottom
                placed = TextItem(block, at: Point(r.midX, y), anchor: TextAnchor(horizontal: .middle, vertical: vertical),
                                  color: labelColor)
            } else {
                let left = bar.value < 0
                let fitsOutside = left ? r.minX - offset - block.width >= plot.minX : r.maxX + offset + block.width <= plot.maxX
                let out = outside && fitsOutside
                let x = out ? (left ? r.minX - offset : r.maxX + offset) : (left ? r.minX + offset : r.maxX - offset)
                let horizontal: TextAnchor.Horizontal = out == left ? .end : .start
                placed = TextItem(block, at: Point(x, r.midY), anchor: TextAnchor(horizontal: horizontal, vertical: .middle),
                                  color: labelColor)
            }
            return .text(placed)
        }
    }

    // MARK: - Legend

    struct LegendMetrics {
        var fontSize: Double
        var marker: Double { fontSize * 0.75 }
        var markerSpacing: Double { fontSize * 0.35 }
        var itemSpacing: Double { fontSize * 0.5 }
    }

    /// Titled series, which are the ones the legend lists.
    var legendEntries: [(index: Int, series: XYChartDiagram.Series)] {
        guard flag("showLegend", true) else { return [] }
        return diagram.series.enumerated().compactMap { $1.title?.isEmpty == false ? ($0, $1) : nil }
    }

    func legendSize(available: Size) -> Size {
        let entries = legendEntries
        guard !entries.isEmpty else { return .zero }
        let metrics = LegendMetrics(fontSize: setting("legendFontSize", 14))
        let padding = setting("legendPadding", 10)
        let textWidth = entries.map { context.label($0.series.title ?? "", size: metrics.fontSize).width }.max() ?? 0
        let count = Double(entries.count)
        return Size(padding * 2 + metrics.marker + metrics.markerSpacing + textWidth,
                    padding * 2 + count * metrics.fontSize + (count - 1) * metrics.itemSpacing)
    }

    func legendItems(_ layout: Layout) -> [SceneItem] {
        guard layout.legendSize.width > 0 else { return [] }
        let metrics = LegendMetrics(fontSize: setting("legendFontSize", 14))
        let padding = setting("legendPadding", 10)
        let start = Point(layout.legendOrigin.x + padding, layout.legendOrigin.y + padding)
        let row = metrics.fontSize + metrics.itemSpacing
        var items: [SceneItem] = []
        for (position, entry) in legendEntries.enumerated() {
            let top = start.y + Double(position) * row
            let midY = top + metrics.marker / 2
            if entry.series.kind == .bar {
                items.append(.shape(ShapeItem(.rect(Rect(x: start.x, y: top, width: metrics.marker, height: metrics.marker)),
                                              fill: plotColor(entry.index))))
            } else {
                items.append(.shape(ShapeItem(.polyline([Point(start.x, midY), Point(start.x + metrics.marker, midY)]),
                                              stroke: Stroke(strokeColor(entry.index), width: 2))))
            }
            let block = context.label(entry.series.title ?? "", size: metrics.fontSize)
            items.append(.text(TextItem(block, at: Point(start.x + metrics.marker + metrics.markerSpacing, midY),
                                        anchor: .leading, color: self.color("legendTextColor"))))
        }
        return [.group(GroupItem(role: "legend", items: items))]
    }
}
