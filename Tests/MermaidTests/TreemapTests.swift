import Testing
@testable import Mermaid

@Suite("Treemap diagrams")
struct TreemapTests {
    func parse(_ source: String) throws -> TreemapDiagram {
        try #require(try Mermaid.parse(source).diagram as? TreemapDiagram)
    }

    let sample = """
    treemap-beta
    title Products
    "Products"
        "Electronics":::hot
            "Phones": 50
            "Computers": 30
            "Accessories": 20
        "Clothing"
            "Men's", 40
            "Women's": 1,000:::cool %% comma separators are allowed
    classDef hot fill:#f96,stroke:#333,stroke-width:2px;
    classDef cool color:#fff
    """

    @Test func buildsTheHierarchyFromIndentation() throws {
        let d = try parse(sample)
        #expect(d.title == "Products")
        #expect(d.roots.count == 1)
        let products = d.roots[0]
        #expect(products.isSection && products.children.map(\.name) == ["Electronics", "Clothing"])
        #expect(products.children[0].className == "hot")
        #expect(products.children[0].children.map(\.value) == [50, 30, 20])
        #expect(products.children[1].children[1].value == 1000)
        #expect(products.children[1].children[1].className == "cool")
        #expect(products.total == 1140)
        #expect(d.classDefinitions["hot"]?.fill == Color(hex: 0xFF9966))
        #expect(d.classDefinitions["cool"]?.textColor == .white)
    }

    @Test func leavesNeverTakeChildrenAndMultipleRootsAreKept() throws {
        let d = try parse("""
        treemap
        "A"
          "leaf": 1
            "deeper": 2
        "B"
          "x": 3
        """)
        #expect(d.roots.map(\.name) == ["A", "B"])
        // Like mermaid.js, a row under a leaf joins the leaf's section.
        #expect(d.roots[0].children.map(\.name) == ["leaf", "deeper"])
    }

    @Test func errorsAreLocated() {
        func location(_ source: String) -> String? {
            do { _ = try parse(source); return nil } catch let e as MermaidError { return e.location?.description } catch { return nil }
        }
        #expect(location("treemap\n\"A\"\n  bare: 1") == "3:3")
        #expect(location("treemap\n\"A\"\n  \"b\": x") == "3:8")
        #expect(location("treemap\n\"A\":::") == "2:7")
        #expect(location("treemap\n\"A\" junk") == "2:5")
        #expect(location("treemap\n\"open") == "2:1")
    }

    func cells(_ source: String) throws -> [TreemapLayout.Cell] {
        let context = RenderContext(measurer: ApproximateTextMeasurer())
        return TreemapSceneBuilder(diagram: try parse(source), context: context).cells()
    }

    @Test func leafAreasAreProportionalToValues() throws {
        // Without padding, leaf areas divide the canvas exactly by value.
        let layout = TreemapLayout(headerHeight: 0, sectionPadding: 0, innerPadding: 0, rounds: false)
        let values: [Double] = [6, 6, 4, 3, 2, 2, 1]
        let roots = values.enumerated().map { TreemapDiagram.Node(name: "n\($0.offset)", value: $0.element) }
        let bounds = Rect(x: 0, y: 0, width: 600, height: 400)
        let cells = layout.layout(roots, in: bounds)
        let leaves = cells.dropFirst()
        let total = values.reduce(0, +)
        for cell in leaves {
            let expected = cell.value / total * bounds.width * bounds.height
            #expect(abs(cell.frame.width * cell.frame.height - expected) < 0.01)
        }
        // The squarified layout keeps cells reasonably square.
        #expect(leaves.allSatisfy { max($0.frame.width / $0.frame.height, $0.frame.height / $0.frame.width) < 4 })
    }

    @Test func cellsNestInsideTheirSectionsWithoutOverlapping() throws {
        let cells = try cells(sample)
        for (i, cell) in cells.enumerated() where cell.depth > 0 {
            let parent = cells[cell.parent ?? 0]
            #expect(parent.frame.contains(cell.frame.origin) && parent.frame.contains(Point(cell.frame.maxX, cell.frame.maxY)))
            if cell.depth > 1 { #expect(cell.frame.minY >= parent.frame.minY + TreemapSceneBuilder.headerHeight) }
            for sibling in parent.children where sibling != i {
                #expect(!cell.frame.intersects(cells[sibling].frame))
            }
        }
        // Largest first, as mermaid.js sorts.
        let phones = try #require(cells.first { $0.node.name == "Phones" })
        let accessories = try #require(cells.first { $0.node.name == "Accessories" })
        #expect(phones.frame.width * phones.frame.height > accessories.frame.width * accessories.frame.height)
    }

    @Test func zeroValuedNodesAreOmitted() throws {
        let cells = try cells("treemap\n\"A\"\n  \"a\": 0\n  \"b\": 5\n\"Empty\"")
        #expect(cells.map(\.node.name) == ["", "A", "b"])
    }

    @Test func drawsSectionsLeavesAndFormattedValues() throws {
        let source = "---\nconfig:\n  treemap:\n    valueFormat: '$0,0'\n---\n" + sample
        let scene = try Mermaid.render(source, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        let svg = scene.svg
        #expect(svg.components(separatedBy: "class=\"treemap-section\"").count - 1 == 3)
        #expect(svg.components(separatedBy: "class=\"treemap-leaf\"").count - 1 == 5)
        #expect(svg.contains(">$1,140</text>") && svg.contains(">Phones</text>"))
        #expect(svg.contains("fill=\"#ff9966\""))
        let hidden = try Mermaid.render("---\nconfig:\n  treemap:\n    showValues: false\n---\n" + sample,
                                        options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(!hidden.svg.contains(">50</text>"))
    }
}
