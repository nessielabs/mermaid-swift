import Testing
@testable import Mermaid

@Suite("Pie layout")
struct PieLayoutTests {
    let options = RenderOptions(measurer: ApproximateTextMeasurer())

    func texts(_ items: [SceneItem]) -> [TextItem] {
        items.flatMap { item -> [TextItem] in
            switch item {
            case .text(let text): return [text]
            case .group(let group): return texts(group.items)
            case .shape: return []
            }
        }
    }

    func groups(_ items: [SceneItem], role: String) -> [GroupItem] {
        items.flatMap { item -> [GroupItem] in
            guard case .group(let group) = item else { return [] }
            return (group.role == role ? [group] : []) + groups(group.items, role: role)
        }
    }

    @Test func anglesCoverTheCircleInSourceOrder() {
        let pie = PieDiagram(slices: [.init(label: "A", value: 386), .init(label: "B", value: 85), .init(label: "C", value: 15)])
        let arcs = pie.arcs
        #expect(arcs.map(\.slice.label) == ["A", "B", "C"])
        #expect(arcs.first?.startAngle == 0)
        #expect(abs((arcs.last?.endAngle ?? 0) - 360) < 1e-9)
        for (a, b) in zip(arcs, arcs.dropFirst()) { #expect(a.endAngle == b.startAngle) }
        let sweep = arcs.reduce(0) { $0 + $1.endAngle - $1.startAngle }
        #expect(abs(sweep - 360) < 1e-9)
        #expect(Int(arcs[0].percentage.rounded()) == 79)
    }

    @Test func tinySlicesLeaveTheCircleButStayInTheLegend() throws {
        let pie = PieDiagram(slices: [.init(label: "Big", value: 995), .init(label: "Tiny", value: 5)])
        #expect(pie.arcs.map(\.slice.label) == ["Big"])
        #expect(pie.arcs[0].endAngle == 360)
        #expect(pie.arcs[0].percentage == 99.5)
        let scene = try pie.scene(in: RenderContext(measurer: ApproximateTextMeasurer()))
        #expect(groups(scene.items, role: "legend").count == 2)
        #expect(groups(scene.items, role: "pieCircle").count == 1)
    }

    @Test func zeroTotalDrawsNoSlices() throws {
        let pie = PieDiagram(slices: [.init(label: "A", value: 0)])
        #expect(pie.arcs.isEmpty)
        let scene = try pie.scene(in: RenderContext(measurer: ApproximateTextMeasurer()))
        #expect(scene.size.width > 0 && scene.size.height > 0)
    }

    @Test func percentagesAndLegendValues() throws {
        let scene = try Mermaid.render("""
        pie showData title Key elements
            "Calcium" : 42.96
            "Potassium" : 50.05
            "Magnesium" : 10.01
            "Iron" :  5
        """, options: options)
        let strings = texts(scene.items).map { $0.block.lines.flatMap(\.runs).map(\.text).joined() }
        #expect(strings.contains("Key elements"))
        #expect(strings.filter { $0.hasSuffix("%") } == ["40%", "46%", "9%", "5%"])
        #expect(strings.contains("Calcium [42.96]") && strings.contains("Iron [5]"))
    }

    @Test func everythingFitsInsideTheScene() throws {
        for position in ["top", "bottom", "left", "right", "center"] {
            let scene = try Mermaid.render("""
            %%{init: {"pie": {"legendPosition": "\(position)"}}}%%
            pie title A rather long title for a small pie
                "An exceptionally long legend label" : 3
                "B" : 1
            """, options: options)
            let frame = Rect(x: 0, y: 0, width: scene.size.width, height: scene.size.height)
            for item in scene.items {
                guard let box = item.bounds else { continue }
                #expect(box.minX >= -0.5 && box.minY >= -0.5 && box.maxX <= frame.maxX + 0.5 && box.maxY <= frame.maxY + 0.5,
                        "\(position): \(box) outside \(frame)")
            }
        }
    }

    @Test func legendDoesNotOverlapThePie() throws {
        for position in ["left", "right", "top", "bottom"] {
            let scene = try Mermaid.render("""
            %%{init: {"pie": {"legendPosition": "\(position)"}}}%%
            pie
                "Dogs and other quite long labels" : 3
                "Cats" : 1
            """, options: options)
            let circle = try #require(groups(scene.items, role: "pieCircle").compactMap { SceneItem.group($0).bounds }
                .reduce(nil) { $0?.union($1) ?? $1 })
            for legend in groups(scene.items, role: "legend") {
                let box = try #require(SceneItem.group(legend).bounds)
                #expect(!box.intersects(circle), "\(position)")
            }
        }
    }

    @Test func highlightedSliceGrowsAndDonutLeavesAHole() throws {
        let pie = PieDiagram(slices: [.init(label: "A", value: 1), .init(label: "B", value: 1)])
        let config = ConfigValue.object(["pie": .object(["highlightSlice": .string("B"), "donutHole": .number(0.5)])])
        let scene = try pie.scene(in: RenderContext(measurer: ApproximateTextMeasurer(), config: config))
        let slices = groups(scene.items, role: "pieCircle")
        let a = try #require(SceneItem.group(slices[0]).bounds), b = try #require(SceneItem.group(slices[1]).bounds)
        #expect(b.height > a.height)
        // A ring segment stays between its radii; a plain slice meets the center.
        let ring = PieSceneBuilder.sector(outer: 100, inner: 40, from: 10, to: 80)
        let ends = ring.elements.compactMap { element -> Point? in
            switch element {
            case .move(let p), .line(let p), .curve(_, _, let p): return p
            case .close: return nil
            }
        }
        #expect(ends.allSatisfy { $0.length >= 40 - 1e-9 && $0.length <= 100 + 1e-9 })
        #expect(PieSceneBuilder.sector(outer: 100, inner: 0, from: 10, to: 80).elements.first == .move(.zero))
    }
}
