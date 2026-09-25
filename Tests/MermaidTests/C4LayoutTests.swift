import Testing
@testable import Mermaid

@Suite("C4 layout and rendering")
struct C4LayoutTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func diagram(_ source: String) throws -> C4Diagram {
        try #require(try Mermaid.parse(source).diagram as? C4Diagram)
    }

    func layout(_ d: C4Diagram) -> (C4Layout, [String: C4ElementBox]) {
        let builder = C4SceneBuilder(diagram: d, context: context)
        var boxes: [String: C4ElementBox] = [:]
        for e in d.elements { boxes[e.alias] = C4ElementBox(e, style: builder.style(of: e), palette: builder.palette, measurer: context.measurer) }
        let headers = Dictionary(uniqueKeysWithValues: d.boundaries.map {
            ($0.alias, C4BoundaryHeader($0, palette: builder.palette, measurer: context.measurer).size) })
        let input = C4Layout.Input(elementSizes: boxes.mapValues(\.size), headerSizes: headers,
                                   shapesPerRow: d.shapesPerRow ?? 4, boundariesPerRow: d.boundariesPerRow ?? 2,
                                   shapeGap: Size(80, 80), boundaryGap: 50, inset: 20)
        return (C4Layout.compute(d, input), boxes)
    }

    static let banking = """
    C4Context
      title System Context
      Enterprise_Boundary(b0, "Bank") {
        Person(a, "Customer A", "A customer of the bank, with personal bank accounts.")
        Person(b, "Customer B")
        System(s, "Internet Banking", "Allows customers to view information about their accounts.")
        Enterprise_Boundary(b1, "Inner") {
          SystemDb_Ext(e, "Mainframe", "Stores all of the core banking information.")
          System_Boundary(b2, "Deepest") {
            System(x, "X")
            System(y, "Y", "A system of the bank.")
          }
          SystemQueue(q, "Queue")
        }
        Boundary(b3, "Third", "boundary") { System(z, "Z") }
      }
      System_Ext(mail, "E-mail")
      Rel(a, s, "Uses")
      BiRel(s, e, "Syncs", "JDBC")
      Rel(s, mail, "Sends e-mails", "SMTP")
      Rel(mail, a, "Sends e-mails to")
    """

    @Test func elementsNeverOverlap() throws {
        let (layout, _) = layout(try diagram(Self.banking))
        let frames = Array(layout.elements.values)
        #expect(frames.count == 9)
        for i in frames.indices { for j in frames.indices where i < j { #expect(!frames[i].intersects(frames[j])) } }
    }

    @Test func boundariesContainTheirMembers() throws {
        let d = try diagram(Self.banking)
        let (layout, _) = layout(d)
        for element in d.elements {
            var parent = element.boundary
            let frame = try #require(layout.elements[element.alias])
            while let alias = parent {
                let box = try #require(layout.boundaries[alias])
                #expect(box.contains(frame.origin) && box.contains(Point(frame.maxX, frame.maxY)), "\(element.alias) in \(alias)")
                parent = d.boundary(alias)?.parent
            }
        }
        // Sibling boundaries do not overlap.
        let siblings = d.boundaries.filter { $0.parent == "b0" }.compactMap { layout.boundaries[$0.alias] }
        #expect(siblings.count == 2 && !siblings[0].intersects(siblings[1]))
    }

    @Test func shapesFillRowsInStatementOrder() throws {
        let d = try diagram("""
        C4Context
        System(a, "A")
        System(b, "B")
        System(c, "C")
        System(d, "D")
        UpdateLayoutConfig($c4ShapeInRow="3")
        """)
        let (layout, _) = layout(d)
        let a = try #require(layout.elements["a"]), b = try #require(layout.elements["b"])
        let c = try #require(layout.elements["c"]), dd = try #require(layout.elements["d"])
        #expect(a.minY == b.minY && b.minY == c.minY && a.maxX < b.minX && b.maxX < c.minX)
        #expect(dd.minY > a.maxY && dd.minX == a.minX)
    }

    @Test func boundariesFollowBoundaryRows() throws {
        let d = try diagram("""
        C4Container
        Container_Boundary(b1, "One") { Container(a, "A") }
        Container_Boundary(b2, "Two") { Container(b, "B") }
        Container_Boundary(b3, "Three") { Container(c, "C") }
        """)
        let (layout, _) = layout(d)
        let b1 = try #require(layout.boundaries["b1"]), b2 = try #require(layout.boundaries["b2"])
        let b3 = try #require(layout.boundaries["b3"])
        #expect(b1.minY == b2.minY && b1.maxX < b2.minX)
        #expect(b3.minY > max(b1.maxY, b2.maxY))
    }

    @Test func textFitsInsideElements() throws {
        let d = try diagram(Self.banking)
        let (layout, boxes) = layout(d)
        for (alias, box) in boxes {
            let frame = try #require(layout.elements[alias])
            for line in box.lines {
                #expect(line.block.width <= frame.width + 0.5)
                #expect(line.top >= 0 && line.top + line.block.height <= frame.height + 0.5, "\(alias)")
            }
        }
        #expect(boxes["a"]?.glyphTop != nil && boxes["s"]?.glyphTop == nil)
        #expect(boxes["e"]?.shape == .database && boxes["q"]?.shape == .queue)
    }

    @Test func paletteDefaultsAndOverrides() throws {
        let d = try diagram("""
        C4Context
        Person(p, "P")
        Container(c, "C")
        Component_Ext(k, "K")
        System(s, "S")
        UpdateElementStyle(s, $bgColor="#ff0000", $fontColor="#00ff00", $borderColor="#0000ff")
        """)
        let (_, boxes) = layout(d)
        #expect(boxes["p"]?.fill == Color(hex: 0x08427B) && boxes["p"]?.text == .white)
        #expect(boxes["c"]?.fill == Color(hex: 0x438DD5))
        #expect(boxes["k"]?.fill == Color(hex: 0xCCCCCC) && boxes["k"]?.text != .white)
        #expect(boxes["s"]?.fill == Color(hex: 0xFF0000) && boxes["s"]?.text == Color(hex: 0x00FF00))
        #expect(boxes["s"]?.stroke == Color(hex: 0x0000FF))
    }

    @Test func sceneDrawsEveryPart() throws {
        let scene = try Mermaid.parse(Self.banking).scene(options: RenderOptions(measurer: ApproximateTextMeasurer()))
        let svg = scene.svg
        for id in ["b0", "b1", "b2", "b3", "a", "s", "mail", "rel_a_s_0", "rel_label_3"] {
            #expect(svg.contains("id=\"\(id)\""), "\(id)")
        }
        #expect(svg.contains(">System Context</text>"))
        #expect(svg.contains("[JDBC]"))
        #expect(scene.size.width > 0 && scene.size.height > 0)
    }

    @Test func dynamicDiagramsNumberRelationships() throws {
        let scene = try Mermaid.render("""
        C4Dynamic
        Container(a, "A")
        Container(b, "B")
        RelIndex(5, a, b, "First")
        Rel(b, a, "Second")
        """, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(scene.svg.contains(">1: First<") && scene.svg.contains(">2: Second<"))
    }

    @Test func labelsStayInsideTheCanvas() throws {
        let scene = try Mermaid.render("""
        C4Context
        System(a, "A")
        System(b, "B")
        Rel(a, b, "Far away")
        UpdateRelStyle(a, b, $offsetX="-900", $offsetY="-400")
        """, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        for item in scene.items {
            let bounds = try #require(item.inkBounds)
            #expect(bounds.minX >= 0 && bounds.minY >= 0 && bounds.maxX <= scene.size.width && bounds.maxY <= scene.size.height)
        }
    }

    @Test func parallelRelationshipsFanApart() throws {
        let scene = try Mermaid.render("""
        C4Context
        System(a, "A")
        System(b, "B")
        Rel(a, b, "One")
        Rel(b, a, "Two")
        """, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        func edge(_ id: String) -> Path? {
            func find(_ items: [SceneItem]) -> Path? {
                for item in items {
                    if case .group(let g) = item {
                        if g.id == id, case .shape(let s)? = g.items.first { return s.path }
                        if let p = find(g.items) { return p }
                    }
                }
                return nil
            }
            return find(scene.items)
        }
        let one = try #require(edge("rel_a_b_0")?.bounds), two = try #require(edge("rel_b_a_1")?.bounds)
        #expect(abs(one.midY - two.midY) > 20)
    }

    @Test func relationshipsBowAroundElementsInTheWay() throws {
        let d = try diagram("""
        C4Context
        System(a, "A")
        System(b, "B")
        System(c, "C")
        Rel(a, c, "Skips b")
        """)
        let (layout, boxes) = layout(d)
        var outlines: [String: [Point]] = [:]
        for (alias, frame) in layout.elements { outlines[alias] = boxes[alias]?.outline(in: frame) }
        let builder = C4SceneBuilder(diagram: d, context: context)
        let renderer = C4RelationshipRenderer(diagram: d, palette: builder.palette, measurer: context.measurer,
                                              outlines: outlines, elementFrames: Array(layout.elements.values),
                                              obstacles: [], background: .white)
        guard case .group(let group)? = renderer.items().lines.first, case .shape(let line)? = group.items.first else {
            Issue.record("no line"); return
        }
        let b = try #require(layout.elements["b"]).insetBy(dx: 2, dy: 2)
        #expect(!line.path.flattened().contains(where: b.contains))
    }
}
