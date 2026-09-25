import Testing
@testable import Mermaid

@Suite("Sankey drawing")
struct SankeySceneTests {
    func builder(_ body: String, config: ConfigValue = .object([:])) throws -> SankeySceneBuilder {
        let prepared = try Preprocessor.prepare("sankey\n" + body)
        let diagram = try SankeyParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
        return SankeySceneBuilder(diagram: diagram, context: RenderContext(measurer: ApproximateTextMeasurer(), config: config))
    }

    func linkShapes(_ b: SankeySceneBuilder) -> [ShapeItem] {
        b.links(b.layout()).compactMap { item in
            guard case .group(let g) = item, case .shape(let s) = g.items[0] else { return nil }
            return s
        }
    }

    @Test func linkColoringModes() throws {
        let body = "A,B,10\nB,C,4"
        let gradient = linkShapes(try builder(body))
        #expect(gradient[0].gradient?.stops.map(\.color) == [Color(hex: 0x4E79A7), Color(hex: 0xF28E2C)])
        #expect(gradient[0].opacity == 0.5)
        func mode(_ value: String) throws -> [ShapeItem] {
            linkShapes(try builder(body, config: .object(["sankey": .object(["linkColor": .string(value)])])))
        }
        #expect(try mode("source")[1].fill == Color(hex: 0xF28E2C))
        #expect(try mode("target")[1].fill == Color(hex: 0xE15759))
        let fixed = try mode("#a1a1a1")
        #expect(fixed.allSatisfy { $0.fill == Color(hex: 0xA1A1A1) && $0.gradient == nil })
    }

    @Test func ribbonsMeetTheirNodes() throws {
        let b = try builder("A,B,10\nA,C,5")
        let layout = b.layout()
        for (shape, link) in zip(linkShapes(b), layout.links) {
            let box = try #require(shape.path.bounds)
            #expect(abs(box.minX - layout.nodes[link.source].x1) < 1e-9)
            #expect(abs(box.maxX - layout.nodes[link.target].x0) < 1e-9)
        }
    }

    @Test func labelsAndValues() throws {
        let b = try builder("Budget,Rent,1200.456\nBudget,Food,400",
                            config: .object(["sankey": .object(["prefix": .string("$"), "suffix": .string(" USD"),
                                                                 "nodeColors": .object(["Rent": .string("#ff0000")])])]))
        let layout = b.layout()
        let labels = b.labels(layout).compactMap { item -> TextItem? in if case .text(let t) = item { return t } else { return nil } }
        let strings = labels.map { $0.block.lines.flatMap(\.runs).map(\.text).joined() }
        #expect(strings == ["Budget $1600.46 USD", "Rent $1200.46 USD", "Food $400 USD"])
        // Left-half nodes label to their right, right-half nodes to their left.
        #expect(labels[0].frame.minX >= layout.nodes[0].x1)
        #expect(labels[1].frame.maxX <= layout.nodes[1].x0)
        #expect(b.nodeColor(1) == Color(hex: 0xFF0000))
        let plain = try builder("A,B,1", config: .object(["sankey": .object(["showValues": .bool(false)])]))
        #expect(plain.labelText(0, plain.layout().nodes[0]) == "A")
    }

    @Test func outlinedLabelsGetAHalo() throws {
        let b = try builder("A,B,10\nB,C,10\nC,D,1", config: .object(["sankey": .object(["labelStyle": .string("outlined")])]))
        #expect(b.labels(b.layout()).count == 4 * 9)
    }

    @Test func everythingFitsTheScene() throws {
        let scene = try Mermaid.render("sankey\nA very long source name,Target,5\nTarget,Another very long sink name,5",
                                       options: RenderOptions(measurer: ApproximateTextMeasurer()))
        for item in scene.items {
            guard let box = item.bounds else { continue }
            #expect(box.minX >= -0.5 && box.minY >= -0.5 && box.maxX <= scene.size.width + 0.5 && box.maxY <= scene.size.height + 0.5)
        }
    }
}
