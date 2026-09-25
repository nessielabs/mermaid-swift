import Foundation

extension GanttDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        let today = today ?? .now()
        let tasks = try schedule(today: today)
        let settings = GanttSettings(context.section("gantt"))
        let layout = GanttLayout.compute(diagram: self, tasks: tasks, settings: settings, context: context, today: today)
        return GanttSceneBuilder(diagram: self, layout: layout, settings: settings, context: context).build()
    }
}

/// Draws a laid-out gantt chart in mermaid.js' order: excluded days,
/// section bands, grid, bars and labels, section titles, the today line.
struct GanttSceneBuilder {
    let diagram: GanttDiagram
    let layout: GanttLayout
    let settings: GanttSettings
    let context: RenderContext
    let palette: GanttPalette

    init(diagram: GanttDiagram, layout: GanttLayout, settings: GanttSettings, context: RenderContext) {
        self.diagram = diagram
        self.layout = layout
        self.settings = settings
        self.context = context
        palette = GanttPalette(theme: context.theme)
    }

    func build() -> Scene {
        var items: [SceneItem] = []
        if !layout.excludedRanges.isEmpty {
            items.append(.group(GroupItem(role: "excludes", items: layout.excludedRanges.map {
                .shape(ShapeItem(.rect($0), fill: palette.excludeBkgColor))
            })))
        }
        items.append(.group(GroupItem(role: "sections", items: layout.rows.map { row in
            .shape(ShapeItem(.rect(row.frame), fill: sectionFill(row.sectionIndex), opacity: 0.2))
        })))
        items.append(axis(top: false))
        if diagram.topAxis || settings.topAxis { items.append(axis(top: true)) }
        items += layout.bars.map(bar)
        items += layout.markers.map(marker)
        items.append(.group(GroupItem(role: "section-titles", items: layout.sections.map(sectionTitle))))
        if let today = todayLine() { items.append(today) }
        if let title = diagram.title ?? context.title, !title.isEmpty {
            let block = context.label(title, size: 18)
            items.append(.text(text(block, baselineAt: Point(layout.width / 2, settings.titleTopMargin),
                                    alignment: .center, color: palette.titleColor)))
        }

        // Labels placed beside bars may run past the nominal width; grow
        // the canvas instead of clipping them.
        let rightmost = layout.bars.map { $0.labelFrame.maxX + 5 }.max() ?? 0
        let size = Size(max(layout.width, rightmost), layout.height)
        var plain = context
        plain.title = nil
        return DiagramCanvas(context: plain, margin: 8).scene(content: items, size: size)
    }

    /// mermaid alternates `section0`...`section3`: section color,
    /// alternate, second section color, alternate.
    private func sectionFill(_ index: Int) -> Color {
        switch (index % settings.numberSectionStyles) % 4 {
        case 0: return palette.sectionBkgColor
        case 2: return palette.sectionBkgColor2
        default: return palette.altSectionBkgColor
        }
    }

    /// A text item whose first baseline sits at `point`.
    private func text(_ block: TextBlock, baselineAt point: Point, alignment: TextItem.Alignment,
                      color: Color) -> TextItem {
        let top = point.y - (block.lines.first?.baseline ?? 0)
        let x: Double
        switch alignment {
        case .leading: x = point.x
        case .center: x = point.x - block.width / 2
        case .trailing: x = point.x - block.width
        }
        return TextItem(block, frame: Rect(x: x, y: top, width: block.width, height: block.height),
                        alignment: alignment, color: color)
    }

    // MARK: - Grid

    private func axis(top: Bool) -> SceneItem {
        let gridTop = settings.topPadding + settings.gridLineStartPadding - 50
        let axisY = top ? settings.topPadding : layout.height - 50
        let lineStart = top ? settings.topPadding : gridTop
        let lineEnd = top ? layout.height - settings.gridLineStartPadding : axisY
        var items: [SceneItem] = []
        var lastLabelEnd = -Double.infinity
        let stroke = Stroke(palette.gridColor.withAlpha(palette.gridColor.alpha * 0.8), width: 1)
        for tick in layout.ticks {
            let x = tick.x.rounded() + 0.5
            items.append(.shape(ShapeItem(.polyline([Point(x, lineStart), Point(x, lineEnd)]), stroke: stroke)))
            let block = context.label(tick.label, size: 10)
            // Skip labels that would collide with the previous one.
            guard tick.x - block.width / 2 > lastLabelEnd + 4 else { continue }
            lastLabelEnd = tick.x + block.width / 2
            let baseline = top ? axisY - 3 - 2 : axisY + 3 + 10
            items.append(.text(text(block, baselineAt: Point(tick.x, baseline), alignment: .center,
                                    color: palette.textColor)))
        }
        return .group(GroupItem(role: top ? "top-axis" : "axis", items: items))
    }

    // MARK: - Tasks

    private func bar(_ bar: GanttLayout.Bar) -> SceneItem {
        let task = bar.task.task
        let (fill, stroke) = barColors(task)
        var items: [SceneItem] = []
        let path: Path
        if task.has(.milestone) {
            let side = settings.barHeight * 0.8
            let center = bar.frame.center
            let square = Path.rect(Rect(center: center, size: Size(side, side)), cornerRadius: 3 * 0.8)
            let angle = Double.pi / 4
            path = square.transformed { p in
                let dx = p.x - center.x, dy = p.y - center.y
                return Point(center.x + dx * cos(angle) - dy * sin(angle), center.y + dx * sin(angle) + dy * cos(angle))
            }
        } else {
            path = .rect(bar.frame, cornerRadius: 3)
        }
        items.append(.shape(ShapeItem(path, fill: fill, stroke: Stroke(stroke, width: 2))))

        let clickable = task.link != nil || task.callback != nil
        var block = context.label(task.name, size: settings.fontSize, bold: clickable)
        if task.has(.milestone) {
            block = TextBlock(LabelParser.parse(task.name), font: Font(family: context.theme.fontFamily,
                              size: settings.fontSize, bold: clickable, italic: true), measurer: context.measurer)
        }
        let color = clickable ? palette.taskTextClickableColor : labelColor(task, inside: bar.labelInside)
        items.append(.text(TextItem(block, frame: bar.labelFrame, alignment: bar.labelAlignment, color: color)))
        return .group(GroupItem(id: task.id, role: "task", items: items))
    }

    private func barColors(_ task: GanttDiagram.Task) -> (fill: Color, stroke: Color) {
        let crit = task.has(.crit)
        if task.has(.active) {
            return (palette.activeTaskBkgColor, crit ? palette.critBorderColor : palette.activeTaskBorderColor)
        }
        if task.has(.done) {
            return (palette.doneTaskBkgColor, crit ? palette.critBorderColor : palette.doneTaskBorderColor)
        }
        if crit { return (palette.critBkgColor, palette.critBorderColor) }
        return (palette.taskBkgColor, palette.taskBorderColor)
    }

    /// mermaid's text classes: active and done labels are dark inside
    /// their light bars; outside a bar, labels use the outside color
    /// except active ones.
    private func labelColor(_ task: GanttDiagram.Task, inside: Bool) -> Color {
        if inside {
            return task.has(.active) || task.has(.done) ? palette.taskTextDarkColor : palette.taskTextColor
        }
        return task.has(.active) && !task.has(.done) ? palette.taskTextDarkColor : palette.taskTextOutsideColor
    }

    private func marker(_ marker: GanttLayout.Marker) -> SceneItem {
        let block = context.label(marker.task.task.name, size: 15)
        return .group(GroupItem(id: marker.task.task.id, role: "vert", items: [
            .shape(ShapeItem(.rect(marker.line), fill: palette.vertLineColor)),
            .text(TextItem(block, centeredAt: marker.labelCenter, color: palette.vertLineColor)),
        ]))
    }

    private func sectionTitle(_ section: GanttLayout.SectionTitle) -> SceneItem {
        let block = context.label(section.name, size: settings.sectionFontSize)
        return .text(TextItem(block, frame: Rect(x: 10, y: section.centerY - block.height / 2, width: block.width,
                                                 height: block.height),
                              alignment: .leading, color: palette.titleColor))
    }

    private func todayLine() -> SceneItem? {
        guard let x = layout.todayX else { return nil }
        let style = ElementStyle(css: diagram.todayMarker)
        let stroke = Stroke(style.stroke ?? palette.todayLineColor, width: style.strokeWidth ?? 2, dash: style.strokeDash ?? [])
        let line = Path.polyline([Point(x, settings.titleTopMargin), Point(x, layout.height - settings.titleTopMargin)])
        return .group(GroupItem(role: "today", items: [.shape(ShapeItem(line, stroke: stroke, opacity: style.opacity ?? 1))]))
    }
}
