/// The geometry of a timeline, following mermaid.js' two renderers:
/// left-to-right (periods in a row above a horizontal arrow, events
/// stacked below) and top-down (periods down a vertical arrow, events to
/// its right).
struct TimelineLayout {
    enum Kind: Hashable { case section, period, event }

    struct Node {
        var kind: Kind
        var text: TextBlock
        var frame: Rect
        /// The section color slot (`cScale<n>`).
        var colorIndex: Int
        /// The period this node belongs to (nil for sections).
        var period: Int?
    }

    /// A straight line ending in an arrowhead.
    struct Arrow {
        var from: Point
        var to: Point
        var width: Double
        var dashed: Bool
    }

    var nodes: [Node] = []
    var arrows: [Arrow] = []

    /// The union of every node and arrow.
    var bounds: Rect {
        let points = nodes.flatMap { [$0.frame.origin, Point($0.frame.maxX, $0.frame.maxY)] }
            + arrows.flatMap { [$0.from, $0.to] }
        return Rect.bounding(points) ?? Rect(x: 0, y: 0, width: 0, height: 0)
    }

    struct Metrics {
        var textWidth: Double
        var padding: Double
        var minimumHeight: Double
    }

    static func compute(_ diagram: TimelineDiagram, context: RenderContext) -> TimelineLayout {
        let multicolor = !(context.section("timeline")["disableMulticolor"]?.boolValue ?? false)
        switch diagram.direction {
        case .leftToRight: return horizontal(diagram, context: context, multicolor: multicolor)
        case .topToBottom: return vertical(diagram, context: context, multicolor: multicolor)
        }
    }

    /// A node's text wrapped at `width` and its box height: mermaid's
    /// text height plus half a line and the padding.
    static func block(_ text: String, width: Double, padding: Double, context: RenderContext) -> (TextBlock, Double) {
        let block = context.label(text, maxWidth: width, forceWrap: true)
        return (block, (block.height + context.theme.fontSize * 1.1 * 0.5 + padding).rounded(.up))
    }

    /// Color slots per period: its section's, or with no sections, one per
    /// period unless multicolor is disabled.
    static func colorIndex(_ diagram: TimelineDiagram, period i: Int, multicolor: Bool) -> Int {
        if let section = diagram.periods[i].section { return section }
        return diagram.sections.isEmpty && multicolor ? i : 0
    }

    // MARK: - Left to right

    private static func horizontal(_ d: TimelineDiagram, context: RenderContext, multicolor: Bool) -> TimelineLayout {
        let padding = 20.0, textWidth = 150.0, nodeWidth = 190.0, pitch = 200.0
        var layout = TimelineLayout()
        let hasSections = !d.sections.isEmpty
        let maxSectionHeight = d.sections.map { block($0, width: textWidth, padding: padding, context: context).1 + 20 }.max() ?? 0
        let maxTaskHeight = d.periods.map { block($0.text, width: textWidth, padding: padding, context: context).1 + 20 }.max() ?? 0
        let eventHeights = d.periods.map { period in
            period.events.map { max(block($0, width: textWidth, padding: padding, context: context).1, 50) }
        }
        let maxEventLength = eventHeights.map { $0.reduce(0, +) + 10 * Double(max($0.count - 1, 0)) }.max() ?? 0
        let taskY = hasSections ? 50 + maxSectionHeight + 50 : 50

        var x = 200.0
        func place(period i: Int, at x: Double, color: Int) {
            let (text, height) = block(d.periods[i].text, width: textWidth, padding: padding, context: context)
            layout.nodes.append(Node(kind: .period, text: text,
                                     frame: Rect(x: x, y: taskY, width: nodeWidth, height: max(height, maxTaskHeight)),
                                     colorIndex: color, period: i))
            var y = taskY + 200
            for (event, eventHeight) in zip(d.periods[i].events, eventHeights[i]) {
                let (text, _) = block(event, width: textWidth, padding: padding, context: context)
                layout.nodes.append(Node(kind: .event, text: text,
                                         frame: Rect(x: x, y: y, width: nodeWidth, height: eventHeight),
                                         colorIndex: color, period: i))
                y += eventHeight + 10
            }
            let lineX = x + nodeWidth / 2
            layout.arrows.append(Arrow(from: Point(lineX, taskY + maxTaskHeight),
                                       to: Point(lineX, taskY + maxTaskHeight + 200 + maxEventLength),
                                       width: 2, dashed: true))
        }

        if hasSections {
            for (s, name) in d.sections.enumerated() {
                let members = d.periods.indices.filter { d.periods[$0].section == s }
                let span = pitch * Double(max(members.count, 1))
                let (text, height) = block(name, width: span - 50, padding: padding, context: context)
                layout.nodes.append(Node(kind: .section, text: text,
                                         frame: Rect(x: x, y: 50, width: span - 10, height: max(height, maxSectionHeight)),
                                         colorIndex: s, period: nil))
                for (k, i) in members.enumerated() { place(period: i, at: x + pitch * Double(k), color: s) }
                x += span
            }
            // Periods declared before the first section follow the sections.
            for i in d.periods.indices where d.periods[i].section == nil {
                place(period: i, at: x, color: 0)
                x += pitch
            }
        } else {
            for i in d.periods.indices {
                place(period: i, at: x, color: colorIndex(d, period: i, multicolor: multicolor))
                x += pitch
            }
        }

        let axisY = taskY + maxTaskHeight + 50
        let right = max(x - 10, 200 + nodeWidth)
        layout.arrows.append(Arrow(from: Point(150, axisY), to: Point(right + 60, axisY), width: 4, dashed: false))
        return layout
    }

    // MARK: - Top down

    private static func vertical(_ d: TimelineDiagram, context: RenderContext, multicolor: Bool) -> TimelineLayout {
        let padding = 5.0, nodeWidth = 200.0, eventWidth = 300.0
        let leftWidth = nodeWidth + 2 * padding + 20, rightWidth = eventWidth + 2 * padding + 50
        let axisX = 200 + leftWidth
        var layout = TimelineLayout()
        let maxTaskHeight = d.periods.map { block($0.text, width: nodeWidth, padding: padding, context: context).1 }.max() ?? 0
        let eventHeights = d.periods.map { period in
            period.events.map { block($0, width: eventWidth, padding: padding, context: context).1 }
        }
        let maxEventStack = eventHeights.map { $0.reduce(0, +) + 10 * Double(max($0.count - 1, 0)) }.max() ?? 0
        let spacing = max(maxTaskHeight, maxEventStack) + 30
        let sectionWidth = leftWidth + rightWidth - 2 * padding
        let maxSectionHeight = d.sections.map { block($0, width: sectionWidth, padding: padding, context: context).1 }.max() ?? 0

        var y = 50.0
        func place(period i: Int, at y: Double, color: Int) {
            let (text, height) = block(d.periods[i].text, width: nodeWidth, padding: padding, context: context)
            let width = nodeWidth + 2 * padding
            layout.nodes.append(Node(kind: .period, text: text,
                                     frame: Rect(x: axisX - 20 - width, y: y, width: width, height: max(height, maxTaskHeight)),
                                     colorIndex: color, period: i))
            var eventY = y
            for (event, height) in zip(d.periods[i].events, eventHeights[i]) {
                let (text, _) = block(event, width: eventWidth, padding: padding, context: context)
                let frame = Rect(x: axisX + 50, y: eventY, width: eventWidth + 2 * padding, height: height)
                layout.nodes.append(Node(kind: .event, text: text, frame: frame, colorIndex: color, period: i))
                layout.arrows.append(Arrow(from: Point(axisX, frame.midY), to: Point(frame.minX, frame.midY),
                                           width: 2, dashed: true))
                eventY += height + 10
            }
        }

        var sectionOrder: [Int?] = d.sections.indices.map { $0 }
        if d.periods.contains(where: { $0.section == nil }) && !d.sections.isEmpty { sectionOrder.append(nil) }
        if d.sections.isEmpty {
            for i in d.periods.indices {
                place(period: i, at: y, color: colorIndex(d, period: i, multicolor: multicolor))
                y += spacing
            }
        } else {
            for section in sectionOrder {
                let members = d.periods.indices.filter { d.periods[$0].section == section }
                var top = y
                if let section {
                    let (text, height) = block(d.sections[section], width: sectionWidth, padding: padding, context: context)
                    let frame = Rect(x: axisX - leftWidth, y: y, width: sectionWidth + 2 * padding,
                                     height: max(height, maxSectionHeight))
                    layout.nodes.append(Node(kind: .section, text: text, frame: frame, colorIndex: section, period: nil))
                    top = frame.maxY + 20
                }
                for (k, i) in members.enumerated() {
                    place(period: i, at: top + spacing * Double(k), color: section ?? 0)
                }
                y = top + spacing * Double(max(members.count, 1))
            }
        }
        let fontSize = context.theme.fontSize
        let bottom = layout.nodes.map(\.frame.maxY).max() ?? y
        layout.arrows.insert(Arrow(from: Point(axisX, 50 - 2 * fontSize), to: Point(axisX, bottom + fontSize * 0.5 + 20),
                                   width: 4, dashed: false), at: 0)
        return layout
    }
}
