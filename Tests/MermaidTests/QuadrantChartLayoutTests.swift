import Testing
@testable import Mermaid

@Suite("Quadrant chart layout")
struct QuadrantChartLayoutTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func parse(_ body: String) throws -> QuadrantChartDiagram {
        let prepared = try Preprocessor.prepare("quadrantChart\n" + body)
        return try QuadrantChartParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    func group(_ scene: Scene, role: String) -> [SceneItem] {
        scene.items.compactMap { item -> [SceneItem]? in
            guard case .group(let group) = item, group.role == role else { return nil }
            return group.items
        }.flatMap { $0 }
    }

    func string(_ text: TextItem) -> String { text.block.lines.flatMap(\.runs).map(\.text).joined() }

    @Test func quadrantsTileTheChartArea() throws {
        let d = try parse("title T\nx-axis A --> B\ny-axis C --> D")
        let builder = QuadrantChartSceneBuilder(diagram: d, context: context)
        let q = builder.space().quadrants
        // 500 wide: 5 padding each side, 26-point y-axis band on the left.
        #expect(q == Rect(x: 31, y: 5 + 26 + 40, width: 464, height: 500 - 10 - 26 - 40))
        let scene = try d.scene(in: context)
        let rects = scene.items.compactMap { item -> Rect? in
            guard case .group(let g) = item, g.role == "quadrant" else { return nil }
            return SceneItem.group(g).bounds
        }
        #expect(rects.count == 4)
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] { #expect(!a.insetBy(dx: 0.5, dy: 0.5).intersects(b)) }
        }
        #expect(abs(rects.reduce(0) { $0 + $1.width * $1.height } - q.width * q.height) < 1e-6)
    }

    @Test func pointsMapTheUnitSquareOntoTheQuadrants() throws {
        let d = try parse("x-axis Low --> High\nA: [0, 0]\nB: [1, 1]\nC: [0.25, 0.75]")
        let q = QuadrantChartSceneBuilder(diagram: d, context: context).space().quadrants
        let scene = try d.scene(in: context)
        let centers = group(scene, role: "data-points").compactMap { item -> Point? in
            guard case .shape(let shape) = item, let box = shape.path.bounds else { return nil }
            return box.center
        }
        // Drawn last-declared first.
        let expected = [Point(q.minX + 0.25 * q.width, q.maxY - 0.75 * q.height), Point(q.maxX, q.minY), Point(q.minX, q.maxY)]
        for (center, want) in zip(centers, expected) {
            #expect(abs(center.x - want.x) < 1e-6 && abs(center.y - want.y) < 1e-6)
        }
    }

    @Test func xAxisMovesBelowOncePointsExist() throws {
        let empty = try parse("x-axis Low --> High")
        let emptySpace = QuadrantChartSceneBuilder(diagram: empty, context: context).space()
        #expect(emptySpace.xAxisTop > 0 && emptySpace.xAxisBottom == 0)
        let withPoints = try parse("x-axis Low --> High\nA: [0.5, 0.5]")
        let space = QuadrantChartSceneBuilder(diagram: withPoints, context: context).space()
        #expect(space.xAxisTop == 0 && space.xAxisBottom > 0)
        let labels = group(try withPoints.scene(in: context), role: "labels").compactMap { item -> TextItem? in
            if case .text(let t) = item { return t } else { return nil }
        }
        #expect(labels.allSatisfy { $0.frame.minY > space.quadrants.maxY })
    }

    @Test func quadrantLabelsCenterWithoutPointsAndTopAlignWithThem() throws {
        func label(_ body: String) throws -> (TextItem, Rect) {
            let scene = try parse(body).scene(in: context)
            guard case .group(let g) = scene.items[0], case .shape(let s) = g.items[0], case .text(let t) = g.items[1],
                  let box = s.path.bounds else { throw MermaidError(.semantic, "unexpected scene") }
            return (t, box)
        }
        let (centered, box) = try label("quadrant-1 Plan")
        #expect(abs(centered.frame.midY - box.midY) < 1e-6 && abs(centered.frame.midX - box.midX) < 1e-6)
        let (top, topBox) = try label("quadrant-1 Plan\nA: [0.5, 0.5]")
        #expect(abs(top.frame.minY - (topBox.minY + 5)) < 1e-6)
    }

    @Test func largePointsPushTheirLabelsClear() throws {
        let d = try parse("Big: [0.5, 0.5] radius: 25, stroke-width: 4px")
        let items = group(try d.scene(in: context), role: "data-points")
        guard case .shape(let circle) = items[0], case .text(let label) = items[1], let box = circle.path.bounds else {
            Issue.record("unexpected items"); return
        }
        #expect(label.frame.minY >= box.maxY + 2 - 1e-6)
    }

    @Test func rotatedYAxisLabelsSitInTheirBand() throws {
        let d = try parse("y-axis Low --> High")
        let space = QuadrantChartSceneBuilder(diagram: d, context: context).space()
        let labels = group(try d.scene(in: context), role: "labels").compactMap { item -> TextItem? in
            if case .text(let t) = item { return t } else { return nil }
        }
        #expect(labels.map(string) == ["Low", "High"])
        for label in labels {
            #expect(label.rotation == -90)
            #expect(label.bounds.minX >= 0 && label.bounds.maxX <= space.quadrants.minX)
        }
        #expect(labels[0].bounds.midY > labels[1].bounds.midY)
    }

    @Test func themeVariablesAndConfigApply() throws {
        let config = ConfigValue.object([
            "quadrantChart": .object(["chartWidth": .number(400), "chartHeight": .number(300)]),
            "themeVariables": .object(["quadrant1Fill": .string("#ff0000"), "quadrantPointFill": .string("#00ff00")]),
        ])
        let ctx = RenderContext(theme: Theme(config: config), measurer: ApproximateTextMeasurer(), config: config)
        let d = try parse("A: [0.5, 0.5]")
        let scene = try d.scene(in: ctx)
        #expect(scene.size.width == 400)
        guard case .group(let q1) = scene.items[0], case .shape(let fill) = q1.items[0] else { Issue.record(); return }
        #expect(fill.fill == Color(hex: 0xFF0000))
        guard case .shape(let point) = group(scene, role: "data-points")[0] else { Issue.record(); return }
        #expect(point.fill == Color(hex: 0x00FF00))
    }
}
