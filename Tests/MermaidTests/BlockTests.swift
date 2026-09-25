import Testing
@testable import Mermaid

@Suite("Block diagrams")
struct BlockTests {
    func parse(_ source: String) throws -> BlockDiagram {
        try #require(try Mermaid.parse(source).diagram as? BlockDiagram)
    }

    func location(_ source: String) -> String? {
        do { _ = try parse(source); return nil } catch let e as MermaidError { return e.location?.description } catch { return nil }
    }

    @Test func parsesBlocksShapesAndSpans() throws {
        let d = try parse("""
        block-beta
          columns 3
          a["A label"] b:2 c(round) d(("circle"))
          e((("double"))) f([stadium]) g[[sub]] h[("db")] i>"odd"] j{"diamond"} k{{"hex"}}:3
          l[/"lean r"/] m[\\"lean l"\\] n[/"trap"\\] o[\\"inv"/] p[/"na"]
        """)
        #expect(d.root.columns == 3)
        #expect(d.root.children == ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p"])
        #expect(d.blocks["a"]?.label == "A label" && d.blocks["b"]?.label == "b" && d.blocks["b"]?.span == 2)
        let shapes = ["c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n", "o", "p"].map { d.blocks[$0]?.kind }
        #expect(shapes == [.node(.rounded), .node(.circle), .node(.doubleCircle), .node(.stadium), .node(.subroutine),
                           .node(.cylinder), .node(.asymmetric), .node(.diamond), .node(.hexagon), .node(.leanRight),
                           .node(.leanLeft), .node(.trapezoid), .node(.invertedTrapezoid), .node(.rect)])
        #expect(d.blocks["k"]?.span == 3)
    }

    @Test func parsesSpacesArrowsAndComposites() throws {
        let d = try parse("""
        block
          ida space:3 idb
          arrow<["go"]>(x, down):2
          block:group1:2
            columns auto
            inner
            block
              deepest
            end
          end
          block:2
            wide
          end
        """)
        #expect(d.root.children.filter { d.blocks[$0]?.isSpace == true }.count == 3)
        #expect(d.blocks["arrow"]?.kind == .arrow([.x, .down]) && d.blocks["arrow"]?.span == 2)
        let group = try #require(d.blocks["group1"])
        #expect(group.isComposite && group.span == 2 && group.columns == nil)
        #expect(group.children.first == "inner" && d.blocks[group.children[1]]?.children == ["deepest"])
        // `block:2` is an anonymous composite two columns wide.
        let anonymous = try #require(d.root.children.last.flatMap { d.blocks[$0] })
        #expect(anonymous.isComposite && anonymous.span == 2 && anonymous.children == ["wide"])
    }

    @Test func parsesEdgesAndCreatesTheirBlocks() throws {
        let d = try parse("""
        block
          columns 3
          A space:2
          A --> B
          A -- "label" --> C
          C --o D --x E
          B <-.-> D
          F === G
          H --- I
        """)
        #expect(d.edges.map { "\($0.from)\($0.to)" } == ["AB", "AC", "CD", "DE", "BD", "FG", "HI"])
        #expect(d.edges[1].label == "label")
        #expect(d.edges[2].endMarker == .circle && d.edges[3].endMarker == .cross)
        #expect(d.edges[4].stroke == .dotted && d.edges[4].startMarker == .arrow)
        #expect(d.edges[5].stroke == .thick && d.edges[6].endMarker == .none)
        // Blocks first seen in an edge join the grid where they appear.
        #expect(d.root.children.filter { d.blocks[$0]?.isSpace == false } == ["A", "B", "C", "D", "E", "F", "G", "H", "I"])
    }

    @Test func redeclaringABlockKeepsItsPlace() throws {
        let d = try parse("block\n  a:2 b a[\"Label\"]:1")
        #expect(d.root.children == ["a", "b"])
        #expect(d.blocks["a"]?.label == "Label" && d.blocks["a"]?.span == 2)
    }

    @Test func stylesAndClasses() throws {
        let d = try parse("""
        block
          A B C
          classDef blue fill:#66f,stroke:#333,stroke-width:2px,color:#ff6;
          class A,C blue
          style B fill:#f9F,stroke:#333,stroke-width:4px
        """)
        #expect(d.blocks["A"]?.classes == ["blue"] && d.blocks["C"]?.classes == ["blue"])
        #expect(d.classDefinitions["blue"]?.textColor == Color(hex: 0xFFFF66))
        #expect(d.blocks["B"]?.style.strokeWidth == 4)
    }

    @Test func errorsAreLocated() {
        #expect(location("block\n  block:g\n    a") == "2:3")
        #expect(location("block\n  a\n  end") == "3:3")
        #expect(location("block\n  a[\"open") == "2:5")
        #expect(location("block\n  x<[\"a\"]>(sideways)") == "2:12")
        #expect(location("block\n  a\n  style zz fill:#f00") == "3:3")
        #expect(location("block\n  columns x") == "2:11")
        #expect(location("block\n  a --> ") == "2:9")
    }

    func frames(_ source: String) throws -> [String: Rect] {
        let d = try parse(source)
        return BlockSceneBuilder(diagram: d, context: RenderContext(measurer: ApproximateTextMeasurer())).layout().frames
    }

    @Test func gridColumnsAreUniformAndWrap() throws {
        let f = try frames("block\n  columns 3\n  a[\"A wide one\"] b:2 c:2 d")
        let a = try #require(f["a"]), b = try #require(f["b"]), c = try #require(f["c"]), d = try #require(f["d"])
        #expect(a.minY == b.minY && c.minY == d.minY && c.minY > a.maxY)
        #expect(abs(b.width - (2 * a.width + 8)) < 0.001)
        #expect(abs(c.minX - a.minX) < 0.001 && abs(d.minX - (c.maxX + 8)) < 0.001)
    }

    @Test func blocksNeverOverlapAndStayInsideTheirComposites() throws {
        let source = """
        block
          columns 3
          a:3
          block:group1:2
            columns 2
            h i j k
          end
          g
          block:group2:3
            l m n o p q r
          end
          x(("circle")) y<["y"]>(y) z{"diamond"}
        """
        let d = try parse(source)
        let f = try frames(source)
        for (id, block) in d.blocks where block.isComposite && id != "root" {
            let outer = try #require(f[id])
            for child in block.children where d.blocks[child]?.isSpace == false {
                let inner = try #require(f[child])
                #expect(outer.contains(inner.origin) && outer.contains(Point(inner.maxX, inner.maxY)), "\(child) escapes \(id)")
            }
        }
        for (id, block) in d.blocks where block.isComposite {
            let siblings = block.children.compactMap { f[$0] }
            for i in siblings.indices {
                for j in siblings.indices where j > i { #expect(!siblings[i].intersects(siblings[j]), "overlap in \(id)") }
            }
        }
    }

    @Test func rendersShapesArrowsEdgesAndLabels() throws {
        let source = "block\n  A[\"Start\"] space B\n  A -- \"go\" --> B\n  arr<[\"next\"]>(right)\n  block:grp[\"Group\"]\n    C\n  end"
        let scene = try Mermaid.render(source, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        let svg = scene.svg
        #expect(svg.contains(">Start</text>") && svg.contains(">go</text>") && svg.contains(">next</text>"))
        #expect(svg.contains(">Group</text>") && svg.contains("class=\"block-composite\""))
        #expect(svg.contains("class=\"block-arrow\"") && svg.contains("class=\"edge\""))
        #expect(!svg.contains("space-"))
    }
}
