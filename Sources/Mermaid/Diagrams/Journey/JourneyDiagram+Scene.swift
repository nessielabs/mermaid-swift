import Foundation

extension JourneyDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        let config = context.section("journey")
        let settings = JourneyLayout.Settings(config)
        let layout = JourneyLayout.compute(self, settings: settings, context: context)
        let theme = context.theme
        let palette = JourneyPalette(theme: theme, config: config)
        var items: [SceneItem] = []

        for entry in layout.legend {
            items.append(.group(GroupItem(id: "actor-\(entry.colorIndex)", role: "legend", items: [
                .shape(ShapeItem(.circle(center: entry.dot, radius: JourneyLayout.dotRadius),
                                 fill: palette.actor(entry.colorIndex), stroke: Stroke(.black))),
                .text(TextItem(entry.text, frame: Rect(x: entry.textOrigin.x, y: entry.textOrigin.y,
                                                       width: entry.text.width, height: entry.text.height),
                               alignment: .leading, color: palette.legendText)),
            ])))
        }

        for section in layout.sections {
            let fill = palette.fill(section.colorIndex)
            items.append(.group(GroupItem(role: "section", items: [
                .shape(ShapeItem(.rect(section.frame, cornerRadius: 3), fill: fill, stroke: Stroke(palette.boxBorder))),
                .text(TextItem(section.text, centeredAt: section.frame.center, color: palette.label(on: fill))),
            ])))
        }

        // The axis passes behind the task lines and faces.
        items += Self.arrow(from: layout.axis.from, to: layout.axis.to, color: theme.textColor)

        for (i, task) in layout.tasks.enumerated() {
            let fill = palette.fill(task.colorIndex)
            var group: [SceneItem] = [
                .shape(ShapeItem(.polyline([task.line.top, task.line.bottom]),
                                 stroke: Stroke(palette.taskLine, width: 1, dash: [4, 2]))),
            ]
            group += Self.face(at: task.face, score: task.task.score, palette: palette)
            group.append(.shape(ShapeItem(.rect(task.frame, cornerRadius: 3), fill: fill, stroke: Stroke(palette.boxBorder))))
            for dot in task.actorDots {
                group.append(.shape(ShapeItem(.circle(center: dot.center, radius: JourneyLayout.dotRadius),
                                              fill: palette.actor(dot.index), stroke: Stroke(.black))))
            }
            group.append(.text(TextItem(task.text, centeredAt: task.frame.center, color: palette.label(on: fill))))
            items.append(.group(GroupItem(id: "task\(i)", role: "task", items: group)))
        }

        var bounds = layout.bounds
        if let title = title ?? context.title, !title.isEmpty {
            let size = config["titleFontSize"]?.numberValue ?? 2 * theme.fontSize
            let block = context.label(title, size: size, bold: true)
            let frame = Rect(x: layout.leftMargin, y: bounds.minY - block.height, width: block.width, height: block.height)
            let color = config["titleColor"]?.stringValue.flatMap { Color(css: $0) } ?? theme.titleColor
            items.append(.text(TextItem(block, frame: frame, alignment: .leading, color: color)))
            bounds = bounds.union(frame)
        }
        let content = items.map { $0.offsetBy(dx: -bounds.minX, dy: -bounds.minY) }
        var plain = context
        plain.title = nil
        return DiagramCanvas(context: plain, margin: 10).scene(content: content, size: bounds.size)
    }

    /// A face whose mouth smiles above 3, frowns below 3, and is flat at 3.
    static func face(at center: Point, score: Double, palette: JourneyPalette) -> [SceneItem] {
        let r = JourneyLayout.faceRadius
        let feature = Color(hex: 0x666666)
        var items: [SceneItem] = [
            .shape(ShapeItem(.circle(center: center, radius: r), fill: palette.face,
                             stroke: Stroke(Color(hex: 0x999999), width: 2))),
            .shape(ShapeItem(.circle(center: Point(center.x - r / 3, center.y - r / 3), radius: 1.5), fill: feature,
                             stroke: Stroke(feature, width: 2))),
            .shape(ShapeItem(.circle(center: Point(center.x + r / 3, center.y - r / 3), radius: 1.5), fill: feature,
                             stroke: Stroke(feature, width: 2))),
        ]
        var mouth = Path()
        let mouthRadius = r / 2.1
        if score > 3 {
            mouth.appendArc(center: Point(center.x, center.y + 2), radius: mouthRadius, from: 0, to: 180, connect: false)
        } else if score < 3 {
            mouth.appendArc(center: Point(center.x, center.y + 7), radius: mouthRadius, from: 180, to: 360, connect: false)
        } else {
            mouth = .polyline([Point(center.x - 5, center.y + 7), Point(center.x + 5, center.y + 7)])
        }
        items.append(.shape(ShapeItem(mouth, stroke: Stroke(feature, width: score == 3 ? 1 : 1.2, cap: .round))))
        return items
    }

    /// The journey's arrow: a 4px line with mermaid's arrowhead.
    static func arrow(from: Point, to: Point, color: Color) -> [SceneItem] {
        TimelineDiagram.arrowItems(TimelineLayout.Arrow(from: from, to: to, width: 4, dashed: false), color: color)
    }
}

/// Journey colors: `fillType0`...`fillType7` for sections and tasks,
/// `actor0`... (or `journey.actorColours`) for actors, and `faceColor`.
struct JourneyPalette {
    var fills: [Color]
    var actors: [Color]
    var face: Color
    var boxBorder: Color
    var taskLine: Color
    var legendText: Color
    var theme: Theme

    static let defaultActorColours = ["#8FBC8F", "#7CFC00", "#00FFFF", "#20B2AA", "#B0E0E6", "#FFFFE0"]

    init(theme: Theme, config: ConfigValue) {
        self.theme = theme
        let p = theme.primaryColor, s = theme.secondaryColor
        let derived = [p, s, p.adjusted(hue: 64), s.adjusted(hue: 64), p.adjusted(hue: -64), s.adjusted(hue: -64),
                       p.adjusted(hue: 128), s.adjusted(hue: 128)]
        fills = derived.enumerated().map { i, color in theme.color("fillType\(i)") ?? color }
        let configured = config["actorColours"].flatMap { value -> [Color]? in
            guard case .array(let list) = value else { return nil }
            let colors = list.compactMap { $0.stringValue.flatMap { Color(css: $0) } }
            return colors.isEmpty ? nil : colors
        } ?? Self.defaultActorColours.compactMap { Color(css: $0) }
        actors = configured
        face = theme.color("faceColor") ?? Color(hex: 0xFFF8DC)
        boxBorder = theme.name == .dark ? theme.nodeBorder : Color(hex: 0x666666)
        taskLine = theme.name == .dark ? theme.lineColor : Color(hex: 0x666666)
        legendText = theme.name == .dark ? theme.textColor : Color(hex: 0x666666)
    }

    /// Sections cycle through seven fills, as mermaid's `sectionFills` do.
    func fill(_ index: Int) -> Color { fills[((index % 7) + 7) % 7] }

    func actor(_ index: Int) -> Color {
        theme.color("actor\(index)") ?? actors[((index % actors.count) + actors.count) % actors.count]
    }

    /// Dark text, or light text on dark fills.
    func label(on fill: Color) -> Color {
        Theme.contrast(theme.textColor, fill) >= 3 ? theme.textColor
            : (Theme.contrast(.black, fill) >= Theme.contrast(.white, fill) ? .black : .white)
    }
}
