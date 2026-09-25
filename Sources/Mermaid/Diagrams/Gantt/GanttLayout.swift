/// Gantt settings from `config.gantt`, with mermaid.js' defaults.
struct GanttSettings {
    var titleTopMargin: Double
    var barHeight: Double
    var barGap: Double
    var topPadding: Double
    var rightPadding: Double
    /// The configured left padding, or nil to fit the section titles.
    var leftPadding: Double?
    var gridLineStartPadding: Double
    var fontSize: Double
    var sectionFontSize: Double
    var numberSectionStyles: Int
    var axisFormat: String?
    var tickInterval: String?
    var topAxis: Bool
    var compact: Bool
    var weekday: GanttDiagram.Weekday?
    /// The total width (`useWidth`); nil gives the chart area a fixed width.
    var width: Double?

    /// The chart area width when `useWidth` is not configured. mermaid.js
    /// fills its container; a fixed default keeps output reproducible.
    static let defaultChartWidth = 850.0

    init(_ config: ConfigValue) {
        func number(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }
        titleTopMargin = number("titleTopMargin", 25)
        barHeight = number("barHeight", 20)
        barGap = number("barGap", 4)
        topPadding = number("topPadding", 50)
        rightPadding = number("rightPadding", 75)
        leftPadding = config["leftPadding"]?.numberValue
        gridLineStartPadding = number("gridLineStartPadding", 35)
        fontSize = number("fontSize", 11)
        sectionFontSize = number("sectionFontSize", 11)
        numberSectionStyles = max(1, Int(number("numberSectionStyles", 4)))
        axisFormat = config["axisFormat"]?.stringValue
        tickInterval = config["tickInterval"]?.stringValue
        topAxis = config["topAxis"]?.boolValue ?? false
        compact = config["displayMode"]?.stringValue == "compact"
        weekday = config["weekday"]?.stringValue.flatMap { GanttDiagram.Weekday(rawValue: $0.lowercased()) }
        width = config["useWidth"]?.numberValue
    }
}

/// The geometry of a gantt chart, in chart coordinates (origin at the
/// top left, before the canvas margin), following mermaid.js' renderer.
struct GanttLayout {
    struct Bar {
        var task: ScheduledGanttTask
        /// The bar; for milestones, the square that is drawn rotated 45°.
        var frame: Rect
        var row: Int
        var sectionIndex: Int
        var labelFrame: Rect
        var labelAlignment: TextItem.Alignment
        var labelInside: Bool
    }

    struct Row {
        var frame: Rect
        var sectionIndex: Int
    }

    struct SectionTitle {
        var name: String
        var index: Int
        /// The vertical center of the section's rows.
        var centerY: Double
    }

    struct Tick {
        var date: CivilDateTime
        var x: Double
        var label: String
    }

    struct Marker {
        var task: ScheduledGanttTask
        var line: Rect
        var labelCenter: Point
    }

    var width: Double
    var height: Double
    var leftPadding: Double
    var domain: ClosedRange<Double>
    var chartWidth: Double
    var rows: [Row] = []
    var bars: [Bar] = []
    var markers: [Marker] = []
    var sections: [SectionTitle] = []
    var ticks: [Tick] = []
    var excludedRanges: [Rect] = []
    var todayX: Double?

    /// The x position of a date, rounded like d3's `rangeRound`.
    func x(_ date: CivilDateTime) -> Double {
        let span = domain.upperBound - domain.lowerBound
        return leftPadding + ((date.milliseconds - domain.lowerBound) / span * chartWidth).rounded()
    }
}
