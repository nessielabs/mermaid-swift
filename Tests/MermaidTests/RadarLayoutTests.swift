import Testing
@testable import Mermaid

@Suite("Radar layout")
struct RadarLayoutTests {
    func builder(_ source: String, config: ConfigValue = .object([:])) throws -> RadarSceneBuilder {
        let prepared = try Preprocessor.prepare(source)
        let diagram = try RadarParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
        let ctx = RenderContext(theme: Theme(config: config), measurer: ApproximateTextMeasurer(), config: config)
        return RadarSceneBuilder(diagram: diagram, context: ctx)
    }

    func group(_ items: [SceneItem], role: String) -> [GroupItem] {
        items.compactMap { if case .group(let g) = $0, g.role == role { return g } else { return nil } }
    }

    @Test func spokesStartAtTwelveAndGoClockwise() throws {
        let b = try builder("radar-beta\n axis a, b, c, d\n curve x{1, 1, 1, 1}")
        let top = b.point(0, 100), right = b.point(1, 100), bottom = b.point(2, 100), left = b.point(3, 100)
        #expect(abs(top.x) < 1e-9 && abs(top.y + 100) < 1e-9)
        #expect(abs(right.x - 100) < 1e-9 && abs(right.y) < 1e-9)
        #expect(abs(bottom.y - 100) < 1e-9 && abs(left.x + 100) < 1e-9)
    }

    @Test func valuesScaleBetweenMinAndMaxAndClamp() throws {
        let b = try builder("radar-beta\n axis a, b\n curve x{0, 10}\n min 2\n max 6")
        #expect(b.radius == 300)
        #expect(b.distance(2) == 0 && b.distance(6) == 300 && b.distance(4) == 150)
        #expect(b.distance(-5) == 0 && b.distance(99) == 300)
        let flat = try builder("radar-beta\n axis a\n curve x{0}")
        #expect(flat.distance(0) == 0)
    }

    @Test func graticuleRingsAreEvenlySpaced() throws {
        let b = try builder("radar-beta\n axis a, b, c\n curve x{1, 2, 3}\n ticks 3")
        let rings = b.graticule().compactMap { item -> Double? in
            if case .shape(let s) = item { return s.path.bounds?.width } else { return nil }
        }
        #expect(rings.count == 3)
        for (i, width) in rings.enumerated() { #expect(abs(width - 2 * 300 * Double(i + 1) / 3) < 1e-6) }
        let polygon = try builder("radar-beta\n axis a, b, c, d\n curve x{1, 2, 3, 4}\n graticule polygon")
        guard case .shape(let ring) = polygon.graticule()[0] else { Issue.record(); return }
        #expect(ring.path.elements.filter { if case .line = $0 { return true } else { return false } }.count == 3)
    }

    @Test func curvesPassThroughTheirValues() throws {
        let b = try builder("radar-beta\n axis a, b, c\n curve x{3, 6, 9}\n max 9\n graticule polygon")
        guard case .group(let curve) = b.curves()[0], case .shape(let shape) = curve.items[0] else { Issue.record(); return }
        let vertices = shape.path.elements.compactMap { element -> Point? in
            switch element { case .move(let p), .line(let p): return p; default: return nil }
        }
        let expected = [b.point(0, 100), b.point(1, 200), b.point(2, 300)]
        for (v, e) in zip(vertices, expected) { #expect(v.distance(to: e) < 1e-9) }
        // Smooth curves also pass through every value point.
        let smooth = RadarSceneBuilder.closedCurve(through: expected, tension: 0.17)
        let ends = smooth.elements.compactMap { if case .curve(_, _, let p) = $0 { return p } else { return nil } }
        #expect(ends.count == 3 && ends.allSatisfy { p in expected.contains { $0.distance(to: p) < 1e-9 } })
    }

    @Test func mismatchedCurvesAreSkippedButListed() throws {
        let b = try builder("radar-beta\n axis a, b, c\n curve ok{1, 2, 3}, short{1, 2}")
        #expect(b.curves().count == 1)
        #expect(b.legend().count == 4)
    }

    @Test func curveStylingComesFromTheSectionScaleAndThemeVariables() throws {
        let config = ConfigValue.object(["theme": .string("base"), "themeVariables": .object([
            "cScale1": .string("#00ff00"), "radar": .object(["curveOpacity": .number(0.25)])])])
        let b = try builder("radar-beta\n axis a, b\n curve x{1, 2}, y{2, 1}", config: config)
        guard case .group(let second) = b.curves()[1], case .shape(let shape) = second.items[0] else { Issue.record(); return }
        #expect(shape.stroke?.color == Color(hex: 0x00FF00))
        #expect(shape.fill == Color(hex: 0x00FF00).withAlpha(0.25))
    }

    @Test func titleClearsTheLabelsAndEverythingFits() throws {
        let b = try builder("radar-beta\n title A title\n axis top[\"A long label at the top\"], b, c\n curve x{1, 2, 3}\n curve y{3, 2, 1}")
        let scene = b.build()
        let texts = scene.items.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
        let title = try #require(texts.first)
        let axisLabels = group(scene.items, role: "axes").flatMap(\.items).compactMap { item -> TextItem? in
            if case .text(let t) = item { return t } else { return nil }
        }
        #expect(axisLabels.allSatisfy { !$0.bounds.intersects(title.bounds) })
        for item in scene.items {
            guard let box = item.bounds else { continue }
            #expect(box.minX >= -0.5 && box.minY >= -0.5 && box.maxX <= scene.size.width + 0.5 && box.maxY <= scene.size.height + 0.5)
        }
    }
}
