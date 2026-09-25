/// A gantt task with its start and end resolved to dates.
public struct ScheduledGanttTask: Hashable, Sendable {
    public var task: GanttDiagram.Task
    public var start: CivilDateTime
    /// The end used for dependencies (`after`), extended past excluded days.
    public var end: CivilDateTime
    /// The end the bar is drawn to. When excluded days extend a task, the
    /// bar stops at the last working day instead of covering trailing
    /// excluded days, as in mermaid.js.
    public var renderEnd: CivilDateTime
}

extension GanttDiagram {
    /// Resolves every task's dates, following mermaid.js' rules:
    ///
    /// - `after a b` starts at the latest end of `a` and `b`; `until a b`
    ///   ends at the earliest start. Unknown ids fall back to the start of
    ///   `today`, as mermaid does.
    /// - A task without a start follows the previously declared task.
    /// - Durations (`3d`, `1.5h`, `2w`, ...) are added to the start and
    ///   stretched over excluded days, unless the end is an explicit
    ///   `YYYY-MM-DD` date; `inclusiveEndDates` adds a day to end dates.
    ///
    /// Dependencies may point forward; they resolve in as many passes as
    /// needed. Cycles and invalid dates throw located errors.
    public func schedule(today: CivilDateTime) throws -> [ScheduledGanttTask] {
        var scheduler = GanttScheduler(diagram: self, today: today)
        return try scheduler.run()
    }
}

struct GanttScheduler {
    let diagram: GanttDiagram
    let today: CivilDateTime
    let format: DayjsFormat
    let indexByID: [String: Int]
    var starts: [CivilDateTime?]
    var ends: [CivilDateTime?]
    var renderEnds: [CivilDateTime?]

    init(diagram: GanttDiagram, today: CivilDateTime) {
        self.diagram = diagram
        self.today = today
        format = DayjsFormat(diagram.dateFormat.trimmingWhitespace())
        // Later declarations win, like mermaid's id lookup table.
        indexByID = Dictionary(diagram.tasks.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { _, later in later })
        starts = Array(repeating: nil, count: diagram.tasks.count)
        ends = starts
        renderEnds = starts
    }

    mutating func run() throws -> [ScheduledGanttTask] {
        var remaining = Set(diagram.tasks.indices)
        while !remaining.isEmpty {
            var progressed = false
            for i in diagram.tasks.indices where remaining.contains(i) {
                if try resolve(i) {
                    remaining.remove(i)
                    progressed = true
                }
            }
            if !progressed, let stuck = remaining.min() {
                let task = diagram.tasks[stuck]
                throw MermaidError.semantic("Cannot schedule task '\(task.name)': its 'after' or 'until' references form a cycle",
                                            at: task.location)
            }
        }
        return diagram.tasks.indices.map { i in
            ScheduledGanttTask(task: diagram.tasks[i], start: starts[i]!, end: ends[i]!, renderEnd: renderEnds[i]!)
        }
    }

    /// Resolves task `i`, returning false when it waits on another task.
    private mutating func resolve(_ i: Int) throws -> Bool {
        let task = diagram.tasks[i]
        let start: CivilDateTime
        switch task.start {
        case .previousTaskEnd:
            guard i > 0 else {
                throw MermaidError.semantic("The first task '\(task.name)' needs a start date", at: task.location)
            }
            guard let previous = ends[i - 1] else { return false }
            start = previous
        case .after(let ids):
            let known = ids.compactMap { indexByID[$0] }
            guard !known.isEmpty else { start = today.startOfDay; break }
            let resolved = known.compactMap { ends[$0] }
            guard resolved.count == known.count else { return false }
            start = resolved.max()!
        case .date(let text):
            start = try parseStart(text, task: task)
        }

        var end: CivilDateTime
        var manualEnd = false
        switch task.end {
        case .until(let ids):
            let known = ids.compactMap { indexByID[$0] }
            if known.isEmpty {
                end = today.startOfDay
            } else {
                let resolved = known.compactMap { starts[$0] }
                guard resolved.count == known.count else { return false }
                end = resolved.min()!
            }
        case .dateOrDuration(let text):
            if let date = format.parse(text, reference: today) {
                end = diagram.inclusiveEndDates ? date.adding(1, .day) : date
            } else {
                end = Self.duration(text).map { start.adding($0.amount, $0.unit) } ?? start
            }
            manualEnd = DayjsFormat("YYYY-MM-DD").parse(text, reference: today) != nil
        }

        var renderEnd = end
        if !diagram.excludes.isEmpty, !manualEnd {
            (end, renderEnd) = try stretch(start: start, end: end, task: task)
        }
        starts[i] = start
        ends[i] = end
        renderEnds[i] = renderEnd
        return true
    }

    /// Parses a start date: a timestamp under `X`/`x`, a date in the
    /// chart's format, or, as a fallback like JavaScript's `Date`, an ISO
    /// 8601 date or date-time.
    private func parseStart(_ text: String, task: GanttDiagram.Task) throws -> CivilDateTime {
        if let date = format.parse(text, reference: today) { return date }
        for iso in Self.isoFormats {
            if let date = iso.parse(text, reference: today) { return date }
        }
        throw MermaidError.syntax("Invalid date '\(text)' for date format '\(diagram.dateFormat)' in task '\(task.name)'",
                                  at: task.location)
    }

    static let isoFormats = [
        "YYYY-MM-DD", "YYYY-MM-DD[T]HH:mm", "YYYY-MM-DD[T]HH:mm:ss", "YYYY-MM-DD[T]HH:mm:ss.SSS",
        "YYYY-MM-DD[T]HH:mmZ", "YYYY-MM-DD[T]HH:mm:ssZ", "YYYY-MM-DD[T]HH:mm:ss.SSSZ",
        "YYYY-MM-DD HH:mm", "YYYY-MM-DD HH:mm:ss", "YYYY-MM",
    ].map(DayjsFormat.init)

    /// Parses a duration such as `3d`, `1.5h`, or `250ms`.
    static func duration(_ text: String) -> (amount: Double, unit: CivilDateTime.Unit)? {
        let units: [(String, CivilDateTime.Unit)] = [
            ("ms", .millisecond), ("s", .second), ("m", .minute), ("h", .hour), ("d", .day), ("w", .week),
            ("M", .month), ("y", .year),
        ]
        for (suffix, unit) in units where text.hasSuffix(suffix) {
            let number = text.dropLast(suffix.count)
            guard !number.isEmpty, number.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }),
                  number.first != ".", number.last != ".", number.filter({ $0 == "." }).count <= 1,
                  let amount = Double(number) else { return nil }
            return (amount, unit)
        }
        return nil
    }

    /// Extends `end` by one day per excluded day between the start and the
    /// end, returning the new end and the end to draw (mermaid's
    /// `fixTaskDates`, including its day-after-start convention).
    private func stretch(start: CivilDateTime, end originalEnd: CivilDateTime,
                         task: GanttDiagram.Task) throws -> (CivilDateTime, CivilDateTime) {
        var day = start.adding(1, .day)
        var end = originalEnd
        var renderEnd = originalEnd
        var invalid = false
        let limit = originalEnd.adding(10_000, .day)
        while day <= end {
            if !invalid { renderEnd = end }
            invalid = isExcluded(day)
            if invalid {
                end = end.adding(1, .day)
                if end > limit {
                    throw MermaidError.semantic("Task '\(task.name)' never reaches a day that is not excluded",
                                                at: task.location)
                }
            }
            day = day.adding(1, .day)
        }
        return (end, renderEnd)
    }

    /// Whether `excludes` removes `date` (and `includes` does not restore it).
    func isExcluded(_ date: CivilDateTime) -> Bool {
        let formatted = format.format(date).lowercased()
        let dateOnly = DayjsFormat("YYYY-MM-DD").format(date)
        if diagram.includes.contains(formatted) || diagram.includes.contains(dateOnly) { return false }
        let weekday = date.components.weekday
        if diagram.excludes.contains("weekends") {
            let weekend = diagram.weekend == .friday ? [5, 6] : [6, 0]
            if weekend.contains(weekday) { return true }
        }
        if diagram.excludes.contains(DayjsFormat.weekdayNames[weekday].lowercased()) { return true }
        return diagram.excludes.contains(formatted) || diagram.excludes.contains(dateOnly)
    }
}
