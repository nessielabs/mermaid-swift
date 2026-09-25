import Testing
@testable import Mermaid

@Suite("State diagram layout")
struct StateLayoutTests {
    struct Built {
        var diagram: StateDiagram
        var builder: StateSceneBuilder
        var measured: StateSceneBuilder.Measured
        var layout: LayeredLayout

        func state(_ id: String) -> Rect { builder.stateFrame(id, measured, layout)! }
        func cluster(_ id: String) -> Rect { layout.clusters[id]! }
    }

    func build(_ source: String) throws -> Built {
        let diagram = try #require(try Mermaid.parse(source).diagram as? StateDiagram)
        let builder = StateSceneBuilder(diagram: diagram, context: RenderContext(measurer: ApproximateTextMeasurer()))
        let measured = builder.measure()
        return Built(diagram: diagram, builder: builder, measured: measured,
                     layout: LayeredLayout.compute(builder.graph(measured)))
    }

    /// Groups in a scene by id.
    func groups(_ items: [SceneItem]) -> [String: GroupItem] {
        var result: [String: GroupItem] = [:]
        for item in items {
            guard case .group(let group) = item else { continue }
            if let id = group.id { result[id] = group }
            result.merge(groups(group.items)) { a, _ in a }
        }
        return result
    }

    func contains(_ outer: Rect, _ inner: Rect) -> Bool {
        outer.insetBy(dx: -0.5, dy: -0.5).contains(inner.origin)
            && outer.insetBy(dx: -0.5, dy: -0.5).contains(Point(inner.maxX, inner.maxY))
    }

    @Test func statesFlowDownWithoutOverlapping() throws {
        let b = try build("""
        stateDiagram-v2
            [*] --> Still
            Still --> [*]
            Still --> Moving
            Moving --> Still
            Moving --> Crash
            Crash --> [*]
        """)
        let ids = b.diagram.states.map(\.id)
        for (i, a) in ids.enumerated() {
            for other in ids[(i + 1)...] {
                #expect(!b.state(a).insetBy(dx: 1, dy: 1).intersects(b.state(other)), "\(a) overlaps \(other)")
            }
        }
        #expect(b.state("root_start").maxY < b.state("Still").minY)
        #expect(b.state("Still").maxY < b.state("Moving").minY)
        #expect(b.state("root_start").size == Size(14, 14))
    }

    @Test func compositesContainTheirStatesAndSiblingsStayApart() throws {
        let b = try build("""
        stateDiagram-v2
            [*] --> First
            First --> Second
            state First {
                [*] --> fir
                fir --> [*]
            }
            state Second {
                [*] --> sec
                state Inner { deep }
                sec --> Inner
            }
        """)
        let first = b.cluster("First"), second = b.cluster("Second"), inner = b.cluster("Inner")
        #expect(contains(first, b.state("fir")) && contains(first, b.state("First_start")))
        #expect(contains(second, inner) && contains(inner, b.state("deep")))
        #expect(!first.intersects(second))
        // Isolated composites are laid out as boxes: their contents clear the title band.
        let title = try #require(b.measured.compositeTitles["First"])
        #expect(b.state("First_start").minY > first.minY + title.height + 8)
        // The transition between composites runs from one frame to the other.
        let route = b.layout.edges[1].points
        #expect(first.contains(route[0]) && second.contains(route[route.count - 1]))
    }

    @Test func concurrencyRegionsSitSideBySideOrStacked() throws {
        let body = """
            [*] --> Active
            state Active {
                [*] --> A1
                A1 --> A2
                --
                [*] --> B1
                --
                [*] --> C1
            }
        """
        let tb = try build("stateDiagram-v2\n" + body)
        let regions = tb.diagram.regions.map { tb.cluster($0.id) }.sorted { $0.midX < $1.midX }
        #expect(regions.count == 3)
        for (a, b) in zip(regions, regions.dropFirst()) { #expect(a.maxX <= b.minX) }
        for region in regions { #expect(contains(tb.cluster("Active"), region)) }
        let dividers = tb.builder.regionDividers(of: "Active", body: tb.cluster("Active"), layout: tb.layout)
        #expect(dividers.count == 2)

        let lr = try build("stateDiagram-v2\ndirection LR\n" + body)
        let stacked = lr.diagram.regions.map { lr.cluster($0.id) }.sorted { $0.midY < $1.midY }
        for (a, b) in zip(stacked, stacked.dropFirst()) { #expect(a.maxY <= b.minY) }
    }

    @Test func compositeDirectionsAreHonored() throws {
        let b = try build("""
        stateDiagram-v2
            [*] --> B
            state B {
                direction LR
                a --> b
                b --> c
            }
        """)
        #expect(b.state("a").maxX < b.state("b").minX && b.state("b").maxX < b.state("c").minX)
        #expect(abs(b.state("a").midY - b.state("c").midY) < 0.5)
        // Undirected composites inherit the diagram's direction.
        let inherited = try build("stateDiagram-v2\ndirection LR\nstate X {\n a --> b\n}")
        #expect(inherited.state("a").maxX < inherited.state("b").minX)
    }

    @Test func notesSitBesideTheirStates() throws {
        let b = try build("""
        stateDiagram-v2
            A --> B
            note right of A : right note
            note left of B : left note
        """)
        let scene = groups(b.builder.attachedNotes(b.measured, layout: b.layout).boxes)
        let right = try #require(scene.values.first { $0.id?.hasPrefix("A----note") == true })
        let left = try #require(scene.values.first { $0.id?.hasPrefix("B----note") == true })
        let rightBox = try #require(SceneItem.group(right).bounds), leftBox = try #require(SceneItem.group(left).bounds)
        #expect(rightBox.minX > b.state("A").maxX && abs(rightBox.midY - b.state("A").midY) < 1)
        #expect(leftBox.maxX < b.state("B").minX && abs(leftBox.midY - b.state("B").midY) < 1)

        // Horizontal flows turn notes: `right of` goes below.
        let lr = try build("stateDiagram-v2\ndirection LR\nA --> B\nnote right of A : below")
        let turned = try #require(lr.builder.attachedNotes(lr.measured, layout: lr.layout).boxes.first?.bounds)
        #expect(turned.minY > lr.state("A").maxY && abs(turned.midX - lr.state("A").midX) < 1)
    }

    @Test func forkBarsTurnWithTheFlow() throws {
        let tb = try build("stateDiagram-v2\nstate f <<fork>>\n[*] --> f\nf --> a\nf --> b")
        #expect(tb.state("f").width > tb.state("f").height)
        #expect(tb.state("f").maxY < tb.state("a").minY)
        let lr = try build("stateDiagram-v2\ndirection LR\nstate f <<fork>>\n[*] --> f\nf --> a\nf --> b")
        #expect(lr.state("f").height > lr.state("f").width)
    }

    @Test func descriptionsGrowTheBox() throws {
        let b = try build("stateDiagram-v2\ns1 : Title\ns1 : detail one\ns1 : detail two\ns2 : Title")
        #expect(b.state("s1").height > b.state("s2").height)
        #expect(b.measured.boxes["s1"]?.body?.lines.count == 2)
    }
}
