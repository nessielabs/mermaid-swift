import Testing
@testable import Mermaid

@Suite("Mindmaps")
struct MindmapTests {
    func parse(_ source: String) throws -> MindmapDiagram {
        try #require(try Mermaid.parse(source).diagram as? MindmapDiagram)
    }

    @Test func parsesEveryShape() throws {
        let root = try #require(try parse("""
        mindmap
          root((Center))
            a[Square]
            b(Rounded)
            c((Circle))
            d))Bang((
            e)Cloud(
            f{{Hexagon}}
            Plain text
            (Unnamed)
        """).root)
        #expect(root.id == "root" && root.label == "Center" && root.shape == .circle)
        #expect(root.children.map(\.shape) == [.rect, .rounded, .circle, .bang, .cloud, .hexagon, .default, .rounded])
        #expect(root.children.map(\.label) == ["Square", "Rounded", "Circle", "Bang", "Cloud", "Hexagon", "Plain text", "Unnamed"])
        #expect(root.children[6].id == "Plain text" && root.children[7].id == "Unnamed")
    }

    @Test func indentationBuildsTheTreeLikeMermaid() throws {
        // C is less indented than B but more than A: it becomes A's child.
        let root = try #require(try parse("mindmap\nRoot\n    A\n        B\n      C\n  D").root)
        #expect(root.children.map(\.label) == ["A", "D"])
        #expect(root.children[0].children.map(\.label) == ["B", "C"])
        #expect(root.count == 5)
    }

    @Test func iconsClassesAndMarkdown() throws {
        let root = try #require(try parse("""
        mindmap
          root
            A[A]
            :::urgent large
            B(B)
            ::icon(fa fa-book)
            C["`**Bold** and
            a second line`"]
            D[`bare *markdown*`] :::inline
        """).root)
        #expect(root.children[0].classes == ["urgent", "large"])
        #expect(root.children[1].icon == "fa fa-book")
        #expect(root.children[2].label == "`**Bold** and\na second line`")
        #expect(root.children[3].label == "`bare *markdown*`" && root.children[3].classes == ["inline"])
        #expect(MindmapSceneBuilder.glyph(for: "fa fa-book") == "📖")
        #expect(MindmapSceneBuilder.glyph(for: "mdi mdi-unknown-thing") == "◆")
    }

    @Test func errorsAreLocated() {
        func location(_ source: String) -> String? {
            do { _ = try parse(source); return nil } catch let e as MermaidError { return e.location?.description } catch { return nil }
        }
        #expect(location("mindmap\n  root\n    a\n  second root") == "4:3")
        #expect(location("mindmap\n  root\n    a[unclosed") == "3:6")
        #expect(location("mindmap\n  ::icon(fa)") == "2:3")
        #expect(location("mindmap\n  root\n    a[x] junk") == "3:10")
    }

    let sample = """
    mindmap
      root((mindmap))
        Origins
          Long history
          ::icon(fa fa-book)
          Popularisation
            British popular psychology author Tony Buzan
        Research
          On effectiveness<br/>and features
          On Automatic creation
            Uses
                Creative techniques
                Strategic planning
                Argument mapping
        Tools
          Pen and paper
          Mermaid
    """

    func laidOut(_ source: String) throws -> (MindmapSceneBuilder, [MindmapSceneBuilder.Placed], MindmapLayout) {
        let parsed = try Mermaid.parse(source)
        let builder = MindmapSceneBuilder(diagram: try #require(parsed.diagram as? MindmapDiagram),
                                          context: RenderContext(measurer: ApproximateTextMeasurer(), config: parsed.config))
        let (placed, layout) = builder.layout()
        return (builder, placed, layout)
    }

    @Test(arguments: ["", "---\nconfig:\n  layout: tidy-tree\n---\n"])
    func nodesNeverOverlap(prefix: String) throws {
        let (_, placed, layout) = try laidOut(prefix + sample)
        let frames = layout.frames
        #expect(frames.count == placed.count)
        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].intersects(frames[j]), "\(placed[i].node.label) overlaps \(placed[j].node.label)")
            }
        }
    }

    @Test func radialLayoutGrowsOutwardFromTheRoot() throws {
        let (_, _, layout) = try laidOut(sample)
        #expect(layout.items[0].center == .zero)
        for item in layout.items.dropFirst() {
            let parent = layout.items[item.parent ?? 0]
            #expect(item.center.length > parent.center.length)
        }
    }

    @Test func tidyTreeSplitsBranchesLeftAndRight() throws {
        let (_, _, layout) = try laidOut("---\nconfig:\n  layout: tidy-tree\n---\n" + sample)
        let top = layout.items[0].children.map { layout.items[$0].center.x }
        #expect(top.contains { $0 > 0 } && top.contains { $0 < 0 })
        for item in layout.items.dropFirst() where item.depth > 1 {
            let parent = layout.items[item.parent ?? 0]
            #expect(abs(item.center.x) > abs(parent.center.x))
            #expect((item.center.x > 0) == (parent.center.x > 0))
        }
    }

    @Test func sectionsFollowTopLevelBranches() throws {
        let (_, placed, _) = try laidOut(sample)
        #expect(placed[0].section == nil)
        let sections = Dictionary(placed.map { ($0.node.label, $0.section) }, uniquingKeysWith: { a, _ in a })
        #expect(sections["Origins"] == 0 && sections["Long history"] == 0)
        #expect(sections["Research"] == 1 && sections["Argument mapping"] == 1)
        #expect(sections["Tools"] == 2 && sections["Mermaid"] == 2)
    }

    @Test func rendersEdgesAndNodes() throws {
        let svg = try Mermaid.render(sample, options: RenderOptions(measurer: ApproximateTextMeasurer())).svg
        #expect(svg.components(separatedBy: "class=\"mindmap-edge\"").count - 1 == 14)
        #expect(svg.contains("class=\"mindmap-node section-root\"") && svg.contains(">Popularisation</text>"))
        #expect(try Mermaid.render("mindmap").size.width > 0)
    }
}
