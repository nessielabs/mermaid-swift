extension GanttLayout {
    /// Lays out scheduled tasks: one row per task (or packed rows in
    /// compact mode), a time scale across the chart area, axis ticks,
    /// excluded-day bands, and label placement inside or beside each bar.
    static func compute(diagram: GanttDiagram, tasks: [ScheduledGanttTask], settings s: GanttSettings,
                        context: RenderContext, today: CivilDateTime) -> GanttLayout {
        let gap = s.barHeight + s.barGap
        let rowTasks = tasks.filter { !$0.task.has(.vert) }
        // Sections in order of first use; tasks before any section form
        // an unnamed one.
        var sectionNames: [String] = []
        for task in rowTasks where !sectionNames.contains(task.task.section) { sectionNames.append(task.task.section) }
        let sectionIndex = Dictionary(sectionNames.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })

        let rowOf = s.compact ? compactRows(rowTasks, sections: sectionNames) : Array(rowTasks.indices)
        let rowCount = (rowOf.max() ?? -1) + 1

        let titleWidth = sectionNames.map { context.label($0, size: s.sectionFontSize).width }.max() ?? 0
        let left = s.leftPadding ?? max(75, (titleWidth + 20).rounded(.up))
        let width = s.width ?? left + s.rightPadding + GanttSettings.defaultChartWidth
        let height = 2 * s.topPadding + Double(rowCount) * gap

        var lower = tasks.map(\.start.milliseconds).min() ?? today.startOfDay.milliseconds
        var upper = tasks.map(\.end.milliseconds).max() ?? lower
        if upper <= lower {
            // d3 centers a degenerate domain; widen it by a day around the point.
            lower -= CivilDateTime.msPerDay / 2
            upper = lower + CivilDateTime.msPerDay
        }
        var layout = GanttLayout(width: width, height: height, leftPadding: left, domain: lower...upper,
                                 chartWidth: max(1, width - left - s.rightPadding))

        var rowSections: [Int: Int] = [:]
        for (i, task) in rowTasks.enumerated() {
            let index = sectionIndex[task.task.section] ?? 0
            if rowSections[rowOf[i]] == nil { rowSections[rowOf[i]] = index }
            layout.bars.append(layout.bar(task, row: rowOf[i], section: index, settings: s, context: context))
        }
        layout.rows = rowSections.sorted { $0.key < $1.key }.map { row, section in
            Row(frame: Rect(x: 0, y: Double(row) * gap + s.topPadding - 2, width: width - s.rightPadding / 2, height: gap),
                sectionIndex: section)
        }

        for (index, name) in sectionNames.enumerated() {
            let ys = layout.bars.filter { $0.sectionIndex == index }.map { Double($0.row) * gap }
            guard let first = ys.min(), let last = ys.max() else { continue }
            layout.sections.append(SectionTitle(name: name, index: index,
                                                centerY: s.topPadding + (first + last + gap) / 2))
        }

        for task in tasks where task.task.has(.vert) {
            let x = layout.x(task.start)
            let lineWidth = 0.08 * s.barHeight
            layout.markers.append(Marker(
                task: task,
                line: Rect(x: x, y: s.gridLineStartPadding, width: max(lineWidth, 1.5),
                           height: Double(rowCount) * gap + 2 * s.barHeight),
                labelCenter: Point(x, s.gridLineStartPadding + Double(rowCount) * gap + 60 - 15 * 0.35)))
        }

        layout.ticks = ticks(diagram: diagram, settings: s, layout: layout, context: context)
        layout.excludedRanges = excludedRanges(diagram: diagram, tasks: tasks, layout: layout, settings: s)
        if diagram.todayMarker.lowercased() != "off", layout.domain.contains(today.milliseconds) {
            layout.todayX = layout.x(today)
        }
        return layout
    }

    /// Packs each section's tasks into as few rows as possible, first-fit
    /// by start time (mermaid's `getMaxIntersections`).
    static func compactRows(_ tasks: [ScheduledGanttTask], sections: [String]) -> [Int] {
        var result = Array(repeating: 0, count: tasks.count)
        var offset = 0
        for section in sections {
            let members = tasks.enumerated().filter { $0.element.task.section == section }
                .sorted { ($0.element.start, $0.offset) < ($1.element.start, $1.offset) }
            var rowEnds: [CivilDateTime] = []
            for (i, task) in members {
                if let free = rowEnds.firstIndex(where: { task.start >= $0 }) {
                    rowEnds[free] = task.end
                    result[i] = offset + free
                } else {
                    rowEnds.append(task.end)
                    result[i] = offset + rowEnds.count - 1
                }
            }
            offset += max(rowEnds.count, 1)
        }
        return result
    }

    private func bar(_ task: ScheduledGanttTask, row: Int, section: Int, settings s: GanttSettings,
                     context: RenderContext) -> Bar {
        let y = Double(row) * (s.barHeight + s.barGap) + s.topPadding
        var startX = x(task.start)
        var endX = x(task.renderEnd)
        if task.task.has(.milestone) {
            startX += (x(task.end) - x(task.start)) / 2 - s.barHeight / 2
            endX = startX + s.barHeight
        }
        let frame = Rect(x: startX, y: y, width: max(0, endX - startX), height: s.barHeight)
        let label = context.label(task.task.name, size: s.fontSize)
        let labelSize = Size(label.width, s.barHeight)
        let fits = label.width <= endX - startX
        let chartEndX = endX - leftPadding
        let labelFrame: Rect
        let alignment: TextItem.Alignment
        if fits {
            labelFrame = Rect(center: Point(frame.midX, frame.midY), size: labelSize)
            alignment = .center
        } else if chartEndX + label.width + 1.5 * leftPadding > width {
            labelFrame = Rect(x: startX - 5 - label.width, y: y, width: label.width, height: s.barHeight)
            alignment = .trailing
        } else {
            labelFrame = Rect(x: endX + 5, y: y, width: label.width, height: s.barHeight)
            alignment = .leading
        }
        return Bar(task: task, frame: frame, row: row, sectionIndex: section, labelFrame: labelFrame,
                   labelAlignment: alignment, labelInside: fits)
    }

    /// Axis ticks: the configured `tickInterval` when it gives a sane
    /// number of ticks, otherwise d3's automatic choice.
    private static func ticks(diagram: GanttDiagram, settings s: GanttSettings, layout: GanttLayout,
                              context: RenderContext) -> [Tick] {
        let start = CivilDateTime(milliseconds: layout.domain.lowerBound)
        let stop = CivilDateTime(milliseconds: layout.domain.upperBound)
        let firstWeekday = (diagram.weekday ?? s.weekday ?? .sunday).index
        var interval = CalendarInterval.automatic(from: start, to: stop)
        if let text = diagram.tickInterval ?? s.tickInterval,
           let custom = CalendarInterval(tickInterval: text.trimmingWhitespace(), firstWeekday: firstWeekday),
           (stop.milliseconds - start.milliseconds) / custom.nominalMilliseconds <= 10_000 {
            interval = custom
        }
        let pattern = diagram.axisFormat ?? (diagram.dateFormat.trimmingWhitespace() == "D" ? "%d" : s.axisFormat ?? "%Y-%m-%d")
        let format = StrftimeFormat(pattern)
        // SVG collapses whitespace, so mermaid shows `%e`'s padding as one space.
        func label(_ date: CivilDateTime) -> String {
            format.format(date).split(separator: " ", omittingEmptySubsequences: true).joined(separator: " ")
        }
        return interval.dates(from: start, through: stop).map { Tick(date: $0, x: layout.x($0), label: label($0)) }
    }

    /// Bands for runs of excluded days between the first start and the
    /// last end; skipped beyond five years, like mermaid.
    private static func excludedRanges(diagram: GanttDiagram, tasks: [ScheduledGanttTask], layout: GanttLayout,
                                       settings s: GanttSettings) -> [Rect] {
        guard !diagram.excludes.isEmpty || !diagram.includes.isEmpty,
              let minTime = tasks.map(\.start).min(), let maxTime = tasks.map(\.end).max(),
              maxTime.milliseconds - minTime.milliseconds <= 5 * 365.25 * CivilDateTime.msPerDay else { return [] }
        let scheduler = GanttScheduler(diagram: diagram, today: minTime)
        var ranges: [Rect] = []
        var runStart: CivilDateTime?
        var runEnd = minTime
        var day = minTime
        func close() {
            guard let first = runStart else { return }
            let x0 = layout.x(first.startOfDay)
            let x1 = layout.x(CivilDateTime(milliseconds: runEnd.startOfDay.milliseconds + CivilDateTime.msPerDay - 1))
            ranges.append(Rect(x: x0, y: s.gridLineStartPadding, width: x1 - x0,
                               height: layout.height - s.topPadding - s.gridLineStartPadding))
            runStart = nil
        }
        while day <= maxTime {
            if scheduler.isExcluded(day) {
                if runStart == nil { runStart = day }
                runEnd = day
            } else {
                close()
            }
            day = day.adding(1, .day)
        }
        close()
        return ranges
    }
}
