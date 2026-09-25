/// The geometry of a user journey, following mermaid.js' renderer: an
/// actor legend on the left, section headers above a row of task boxes,
/// a thick arrow beneath them, and each task's face hanging on a dashed
/// line at a height set by its score.
struct JourneyLayout {
    struct LegendEntry {
        var actor: String
        var colorIndex: Int
        var dot: Point
        var text: TextBlock
        var textOrigin: Point
    }

    struct Section {
        var text: TextBlock
        var frame: Rect
        var colorIndex: Int
    }

    struct Task {
        var task: JourneyDiagram.Task
        var text: TextBlock
        var frame: Rect
        var colorIndex: Int
        /// Actor color slots and dot centers along the box's top edge.
        var actorDots: [(index: Int, center: Point, name: String)]
        var line: (top: Point, bottom: Point)
        var face: Point
    }

    static let faceRadius = 15.0
    static let dotRadius = 7.0

    var legend: [LegendEntry] = []
    var sections: [Section] = []
    var tasks: [Task] = []
    var axis: (from: Point, to: Point)
    var leftMargin: Double
    var bounds: Rect

    struct Settings {
        var leftMargin: Double
        var width: Double
        var height: Double
        var taskMargin: Double
        var diagramMarginX: Double
        var diagramMarginY: Double
        var maxLabelWidth: Double
        var taskFontSize: Double

        init(_ config: ConfigValue) {
            func number(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }
            leftMargin = number("leftMargin", 150)
            width = number("width", 150)
            height = number("height", 50)
            taskMargin = number("taskMargin", 50)
            diagramMarginX = number("diagramMarginX", 50)
            diagramMarginY = number("diagramMarginY", 10)
            maxLabelWidth = number("maxLabelWidth", 360)
            taskFontSize = number("taskFontSize", 14)
        }
    }

    static func compute(_ diagram: JourneyDiagram, settings s: Settings, context: RenderContext) -> JourneyLayout {
        let actors = diagram.actors
        let actorIndex = Dictionary(actors.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

        // Legend: a colored dot per actor with its (wrapped) name.
        var legend: [LegendEntry] = []
        var y = 60.0
        var widest = 0.0
        for (i, actor) in actors.enumerated() {
            let text = context.label(actor, maxWidth: s.maxLabelWidth, forceWrap: true)
            legend.append(LegendEntry(actor: actor, colorIndex: i, dot: Point(20, y), text: text,
                                      textOrigin: Point(40, y - min(text.height, 20) / 2)))
            if text.width > 75 { widest = max(widest, text.width) }
            y += max(20, text.height)
        }
        let left = s.leftMargin + widest

        // Boxes grow to fit wrapped labels; mermaid keeps them 50px tall.
        let labelWidth = s.width - 10
        let taskTexts = diagram.tasks.map { context.label($0.name, size: s.taskFontSize, maxWidth: labelWidth, forceWrap: true) }
        let pitch = s.width + s.taskMargin
        var sectionRuns: [(section: Int?, first: Int, count: Int)] = []
        for (i, task) in diagram.tasks.enumerated() {
            if let last = sectionRuns.last, last.section == task.section, i > 0 {
                sectionRuns[sectionRuns.count - 1].count += 1
            } else {
                sectionRuns.append((task.section, i, 1))
            }
        }
        let sectionTexts = sectionRuns.map { run in
            context.label(run.section.map { diagram.sections[$0] } ?? "", size: s.taskFontSize,
                          maxWidth: s.width * Double(run.count) + s.diagramMarginX * Double(run.count - 1) - 10,
                          forceWrap: true)
        }
        let sectionHeight = max(s.height, (sectionTexts.map(\.height).max() ?? 0) + 10)
        let taskTop = 50 + sectionHeight + s.diagramMarginY
        let taskHeight = max(s.height, (taskTexts.map(\.height).max() ?? 0) + 10)
        let axisY = taskTop + taskHeight + 40
        let happiestY = axisY + 100

        var layout = JourneyLayout(legend: legend, axis: (Point(left, axisY), Point(left, axisY)), leftMargin: left,
                                   bounds: Rect(x: 0, y: 0, width: 0, height: 0))
        for (k, run) in sectionRuns.enumerated() {
            let frame = Rect(x: Double(run.first) * pitch + left, y: 50,
                             width: s.width * Double(run.count) + s.diagramMarginX * Double(run.count - 1),
                             height: sectionHeight)
            layout.sections.append(Section(text: sectionTexts[k], frame: frame, colorIndex: k))
            for i in run.first..<(run.first + run.count) {
                let task = diagram.tasks[i]
                let x = Double(i) * pitch + left
                let frame = Rect(x: x, y: taskTop, width: s.width, height: taskHeight)
                let dots = task.actors.enumerated().compactMap { n, actor in
                    actorIndex[actor].map { (index: $0, center: Point(x + 14 + 10 * Double(n), taskTop), name: actor) }
                }
                let score = min(max(task.score, 0), 5)
                let face = Point(frame.midX, happiestY + (5 - score) * 30)
                layout.tasks.append(Task(task: task, text: taskTexts[i], frame: frame, colorIndex: k, actorDots: dots,
                                         line: (Point(frame.midX, taskTop), Point(frame.midX, happiestY + 150)), face: face))
            }
        }

        let contentRight = layout.tasks.map(\.frame.maxX).max() ?? left
        layout.axis = (Point(left, axisY), Point(contentRight + s.taskMargin, axisY))
        let legendRight = legend.map { $0.textOrigin.x + $0.text.width }.max() ?? 0
        let bottom = max(happiestY + 150, legend.map { $0.textOrigin.y + $0.text.height }.max() ?? 0)
        layout.bounds = Rect(x: 0, y: 40, width: max(contentRight + s.taskMargin + 12, legendRight) + 10,
                             height: bottom - 40)
        return layout
    }
}
