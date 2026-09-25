/// An XY chart's data resolved against its axes: the x and y domains
/// (declared or inferred) and every plotted point, following
/// mermaid.js' `xychartDb`.
struct XYChartData: Sendable {
    enum XDomain: Hashable, Sendable {
        case categories([String])
        case linear(Double, Double)
    }

    struct Plot: Sendable {
        var series: XYChartDiagram.Series
        /// Index into the x domain: a category index or an x value.
        var points: [(x: Double, y: Double, label: String?)]
    }

    var x: XDomain
    var y: (Double, Double)
    var plots: [Plot]

    init(_ diagram: XYChartDiagram) {
        let longest = diagram.series.map(\.values.count).max() ?? 0
        switch diagram.xAxis {
        case .categories(let names): x = .categories(names)
        case .range(let range): x = .linear(range.start, range.end)
        // Without an x-axis, points are numbered from 1.
        case nil: x = .linear(1, Double(max(longest, 1)))
        }
        var plots: [Plot] = []
        for series in diagram.series {
            var points: [(Double, Double, String?)] = []
            let label = { (i: Int) in series.pointLabels.indices.contains(i) ? series.pointLabels[i] : nil }
            switch x {
            case .categories(let names):
                // Values beyond the last category are dropped, as in mermaid.js.
                for (i, value) in series.values.prefix(names.count).enumerated() { points.append((Double(i), value, label(i))) }
            case .linear(let start, let end):
                let count = series.values.count
                let step = count > 1 ? (end - start) / Double(count - 1) : 0
                for (i, value) in series.values.enumerated() { points.append((start + Double(i) * step, value, label(i))) }
            }
            plots.append(Plot(series: series, points: points))
        }
        self.plots = plots
        if let range = diagram.yAxisRange {
            y = (range.start, range.end)
        } else {
            y = Self.inferredRange(plots.flatMap { $0.points.map(\.y) }, includeZero: diagram.series.contains { $0.kind == .bar })
        }
    }

    /// The data's extent rounded out to nice tick values. mermaid.js uses
    /// the raw minimum and maximum, which draws the smallest bar with no
    /// height at all; bars here always grow from zero, and the domain is
    /// widened to round numbers so the end ticks are labeled.
    static func inferredRange(_ values: [Double], includeZero: Bool) -> (Double, Double) {
        let finite = values.filter(\.isFinite)
        guard var lo = finite.min(), var hi = finite.max() else { return (0, 1) }
        if includeZero { lo = min(lo, 0); hi = max(hi, 0) }
        if lo == hi {
            if lo == 0 { return (0, 1) }
            let pad = abs(lo) * 0.1
            lo -= pad
            hi += pad
        }
        return ChartTicks.nice(lo, hi)
    }
}

extension XYChartDiagram {
    /// mermaid.js' default `plotColorPalette` for each theme.
    static func defaultPalette(for theme: Theme.Name) -> String {
        switch theme {
        case .default: return "#ECECFF,#8493A6,#FFC3A0,#DCDDE1,#B8E994,#D1A36F,#C3CDE6,#FFB6C1,#496078,#F8F3E3"
        case .dark: return "#3498db,#2ecc71,#e74c3c,#f1c40f,#bdc3c7,#ffffff,#34495e,#9b59b6,#1abc9c,#e67e22"
        case .forest: return "#CDE498,#FF6B6B,#A0D2DB,#D7BDE2,#F0F0F0,#FFC3A0,#7FD8BE,#FF9A8B,#FAF3E0,#FFF176"
        case .neutral: return "#EEE,#6BB8E4,#8ACB88,#C7ACD6,#E8DCC2,#FFB2A8,#FFF380,#7E8D91,#FFD8B1,#FAF3E0"
        case .base: return "#FFF4DD,#FFD8B1,#FFA07A,#ECEFF1,#D6DBDF,#C3E0A8,#FFB6A4,#FFD74D,#738FA7,#FFFFF0"
        }
    }

    /// Parses a comma-separated palette, skipping entries that are not
    /// colors.
    static func palette(_ text: String) -> [Color] {
        text.split(separator: ",").compactMap { Color(css: String($0)) }
    }
}
