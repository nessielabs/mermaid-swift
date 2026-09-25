import Foundation

extension GitGraphDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        GitGraphSceneBuilder(diagram: self, context: context).build()
    }
}

/// Draws a git graph like mermaid.js: dashed branch lanes with colored name
/// badges, thick rounded arrows between commits, commit bullets shaped by
/// type, and commit id labels and tags.
struct GitGraphSceneBuilder {
    let diagram: GitGraphDiagram
    let context: RenderContext
    let config: ConfigValue
    let settings: GitGraphLayout.Settings
    let palette: GitGraphPalette
    var vertical: Bool { diagram.orientation.isVertical }

    init(diagram: GitGraphDiagram, context: RenderContext) {
        self.diagram = diagram
        self.context = context
        config = context.section("gitGraph")
        settings = GitGraphLayout.Settings(config)
        palette = GitGraphPalette(theme: context.theme)
    }

    var branchFont: Font { context.font() }
    /// `commitLabelFontSize` / `tagLabelFontSize` theme variables, 10px by default.
    func fontSize(_ variable: String) -> Double {
        context.config["themeVariables"]?[variable]?.numberValue ?? 10
    }
    var labelFont: Font { context.font(size: fontSize("commitLabelFontSize")) }

    func text(_ string: String, _ font: Font) -> TextBlock {
        TextBlock(RichText(plain: string), font: font, measurer: context.measurer)
    }

    func layout() -> GitGraphLayout {
        GitGraphLayout(diagram: diagram, settings: settings) { text($0, branchFont).width }
    }

    func build() -> Scene {
        var layout = layout()
        var items: [SceneItem] = []
        if settings.showBranches { items += branches(layout) }
        items += layout.arrows().map(arrow)
        var labels: [SceneItem] = []
        for commit in diagram.commits {
            let p = layout.position(of: commit)
            let index = layout.lane(of: commit).index
            items.append(.group(GroupItem(id: commit.id, role: "commit", items: bullet(commit, at: p, colorIndex: index))))
            if settings.showCommitLabel, commit.type != .cherryPick, commit.type != .merge || commit.hasCustomID {
                labels += commitLabel(commit.id, at: p)
            }
            labels += tags(commit.tags, at: p)
        }
        items += labels
        let (content, size) = items.normalizedToOrigin()
        let margin = config["diagramPadding"]?.numberValue ?? 8
        return DiagramCanvas(context: context, margin: margin, title: diagram.title ?? context.title)
            .scene(content: content, size: size)
    }

    // MARK: - Branches

    private func branches(_ layout: GitGraphLayout) -> [SceneItem] {
        var items: [SceneItem] = []
        for branch in diagram.orderedBranches {
            guard let lane = layout.lanes[branch.name] else { continue }
            let from = layout.point(main: layout.start, cross: lane.position)
            let to = layout.point(main: layout.end, cross: lane.position)
            var group: [SceneItem] = [
                .shape(ShapeItem(.polyline([from, to]), stroke: Stroke(palette.branchLine, width: 1, dash: [2, 2]))),
            ]
            let name = text(branch.name, branchFont)
            let size = Size(name.width + 18, name.height + 4)
            let box: Rect
            switch diagram.orientation {
            case .leftToRight:
                let right: Double = -5 - (settings.rotateCommitLabel ? 30 : 0)
                box = Rect(x: right - size.width, y: lane.position - size.height / 2, width: size.width, height: size.height)
            case .topToBottom:
                box = Rect(x: lane.position - size.width / 2, y: 0, width: size.width, height: size.height)
            case .bottomToTop:
                // Mirrors TB, but a little lower: the oldest commit's angled
                // label hangs down toward the badges here.
                let bottom = layout.point(main: 0, cross: 0).y
                box = Rect(x: lane.position - size.width / 2, y: bottom, width: size.width, height: size.height)
            }
            group.append(.shape(ShapeItem(.rect(box, cornerRadius: 4), fill: palette.branchColor(lane.index))))
            group.append(.text(TextItem(name, centeredAt: box.center, color: palette.labelColor(lane.index))))
            items.append(.group(GroupItem(id: "branch-\(branch.name)", role: "branch", items: group)))
        }
        return items
    }

    // MARK: - Arrows

    private func arrow(_ arrow: GitGraphLayout.Arrow) -> SceneItem {
        .shape(ShapeItem(Self.roundedPath(arrow.corners, radius: arrow.radius),
                         stroke: Stroke(palette.branchColor(arrow.colorIndex), width: 8, cap: .round, join: .round)))
    }

    /// An orthogonal polyline with its corners rounded into quarter circles
    /// of `radius` (smaller where a segment is too short).
    static func roundedPath(_ points: [Point], radius: Double) -> Path {
        var path = Path()
        guard let first = points.first else { return path }
        path.move(to: first)
        let k = 0.5523
        for i in points.indices.dropFirst().dropLast() {
            let a = points[i - 1], c = points[i], b = points[i + 1]
            let r = min(radius, a.distance(to: c) / 2, c.distance(to: b) / 2)
            let dirIn = (c - a).normalized, dirOut = (b - c).normalized
            let p = c - dirIn * r, q = c + dirOut * r
            path.line(to: p)
            path.curve(to: q, control1: p + dirIn * (r * k), control2: q - dirOut * (r * k))
        }
        if points.count > 1 { path.line(to: points[points.count - 1]) }
        return path
    }

    // MARK: - Commits

    private func bullet(_ commit: GitGraphDiagram.Commit, at p: Point, colorIndex: Int) -> [SceneItem] {
        let color = palette.branchColor(colorIndex)
        let inner = palette.commitInner
        let circle = ShapeItem(.circle(center: p, radius: 10), fill: color, stroke: Stroke(color))
        switch commit.symbol {
        case .highlight:
            let outer = palette.highlightColor(colorIndex)
            return [
                .shape(ShapeItem(.rect(Rect(center: p, size: Size(20, 20))), fill: outer, stroke: Stroke(outer))),
                .shape(ShapeItem(.rect(Rect(center: p, size: Size(12, 12))), fill: inner, stroke: Stroke(inner))),
            ]
        case .merge:
            return [.shape(circle), .shape(ShapeItem(.circle(center: p, radius: 6), fill: inner, stroke: Stroke(inner)))]
        case .reverse:
            var cross = Path.polyline([Point(p.x - 5, p.y - 5), Point(p.x + 5, p.y + 5)])
            cross.append(.polyline([Point(p.x - 5, p.y + 5), Point(p.x + 5, p.y - 5)]))
            return [.shape(circle), .shape(ShapeItem(cross, stroke: Stroke(inner, width: 3)))]
        case .cherryPick:
            // A cherry: two small fruits hanging from a forked stem.
            let fruit = context.theme.background.isDark ? Color.black : Color.white
            var stems = Path.polyline([Point(p.x + 3, p.y + 1), Point(p.x, p.y - 5)])
            stems.append(.polyline([Point(p.x - 3, p.y + 1), Point(p.x, p.y - 5)]))
            return [
                .shape(circle),
                .shape(ShapeItem(.circle(center: Point(p.x - 3, p.y + 2), radius: 2.75), fill: fruit)),
                .shape(ShapeItem(.circle(center: Point(p.x + 3, p.y + 2), radius: 2.75), fill: fruit)),
                .shape(ShapeItem(stems, stroke: Stroke(fruit))),
            ]
        case .normal:
            return [.shape(circle)]
        }
    }

    /// The commit id under (LR) or beside (TB/BT) the bullet, on a
    /// translucent plate; rotated 45° when `rotateCommitLabel` is set, with
    /// its end tucked against the bullet as in mermaid.js.
    private func commitLabel(_ id: String, at p: Point) -> [SceneItem] {
        let block = text(id, labelFont)
        let plate = Size(block.width + 4, block.height + 4)
        let color = palette.commitLabelBackground.withAlpha(0.5 * palette.commitLabelBackground.alpha)
        if settings.rotateCommitLabel {
            let d = Point(cos(Double.pi / 4), -sin(Double.pi / 4))
            let end = vertical ? Point(p.x - 11.3, p.y + 11.3) : Point(p.x - 2, p.y + 16)
            let center = end - d * (block.width / 2)
            let n = Point(-d.y, d.x)
            let hw = plate.width / 2, hh = plate.height / 2
            let corners = [center - d * hw - n * hh, center + d * hw - n * hh, center + d * hw + n * hh, center - d * hw + n * hh]
            return [.group(GroupItem(role: "commit-label", items: [
                .shape(ShapeItem(.polygon(corners), fill: color)),
                .text(TextItem(block, centeredAt: center, color: palette.commitLabel, rotation: -45)),
            ]))]
        }
        let frame = vertical
            ? Rect(x: p.x - 17 - plate.width, y: p.y - plate.height / 2, width: plate.width, height: plate.height)
            : Rect(x: p.x - plate.width / 2, y: p.y + 13.5, width: plate.width, height: plate.height)
        return [.group(GroupItem(role: "commit-label", items: [
            .shape(ShapeItem(.rect(frame), fill: color)),
            .text(TextItem(block, centeredAt: frame.center, color: palette.commitLabel)),
        ]))]
    }

    /// Luggage-tag shapes pointing at the commit, each with a punched hole:
    /// stacked above the bullet in LR, and angled 45° down and to the right
    /// when vertical (as mermaid.js does), clear of arrows entering the
    /// commit from the side.
    private func tags(_ tags: [String], at p: Point) -> [SceneItem] {
        guard !tags.isEmpty else { return [] }
        let blocks = tags.reversed().map { text($0, context.font(size: fontSize("tagLabelFontSize"))) }
        let width = blocks.map(\.width).max() ?? 0, height = blocks.map(\.height).max() ?? 0
        let angle = vertical ? Double.pi / 4 : 0
        func place(_ q: Point) -> Point {
            let d = q - p
            return Point(p.x + d.x * cos(angle) - d.y * sin(angle), p.y + d.x * sin(angle) + d.y * cos(angle))
        }
        var items: [SceneItem] = []
        for (i, block) in blocks.enumerated() {
            let body: Rect, tip: Point
            if vertical {
                let y = p.y + Double(i) * (height + 8)
                body = Rect(x: p.x + 22, y: y - height / 2 - 2, width: width + 8, height: height + 4)
                tip = Point(p.x + 14, y)
            } else {
                let y = p.y - 19.2 - Double(i) * 20
                body = Rect(x: p.x - width / 2 - 4, y: y - height / 2 - 2, width: width + 8, height: height + 4)
                tip = Point(body.minX - 8, y)
            }
            let outline = [
                Point(tip.x, tip.y + 2), Point(tip.x, tip.y - 2), Point(body.minX, body.minY),
                Point(body.maxX, body.minY), Point(body.maxX, body.maxY), Point(body.minX, body.maxY),
            ].map(place)
            items.append(.group(GroupItem(role: "tag", items: [
                .shape(ShapeItem(.polygon(outline), fill: palette.tagLabelBackground, stroke: Stroke(palette.tagLabelBorder))),
                .shape(ShapeItem(.circle(center: place(Point(tip.x + 4, tip.y)), radius: 1.5), fill: palette.tagHole)),
                .text(TextItem(block, centeredAt: place(Point(body.midX + 1, body.midY)), color: palette.tagLabel,
                               rotation: angle * 180 / .pi)),
            ])))
        }
        return items
    }
}
