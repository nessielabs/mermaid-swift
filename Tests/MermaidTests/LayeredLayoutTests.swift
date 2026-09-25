import Testing
@testable import Mermaid

@Suite("Layered layout")
struct LayeredLayoutTests {
    func graph(_ edges: [(String, String)], direction: LayeredGraph.Direction = .topToBottom,
               clusters: [LayeredGraph.Cluster] = [], membership: [String: String] = [:]) -> LayeredGraph {
        var g = LayeredGraph()
        g.direction = direction
        var ids: [String] = []
        for (a, b) in edges { for id in [a, b] where !ids.contains(id) && !clusters.contains(where: { $0.id == id }) { ids.append(id) } }
        for id in membership.keys where !ids.contains(id) { ids.append(id) }
        g.nodes = ids.map { .init(id: $0, size: Size(60, 30), cluster: membership[$0]) }
        g.edges = edges.map { .init(from: $0.0, to: $0.1) }
        g.clusters = clusters
        return g
    }

    func assertNoOverlaps(_ layout: LayeredLayout) {
        let frames = Array(layout.nodes)
        for i in frames.indices {
            for j in (i + 1)..<frames.count {
                #expect(!frames[i].value.insetBy(dx: 1, dy: 1).intersects(frames[j].value),
                        "\(frames[i].key) overlaps \(frames[j].key)")
            }
        }
    }

    @Test func chainFlowsInDirection() {
        let tb = LayeredLayout.compute(graph([("A", "B"), ("B", "C")]))
        #expect(tb.nodes["A"]!.midY < tb.nodes["B"]!.midY)
        #expect(tb.nodes["B"]!.midY < tb.nodes["C"]!.midY)
        #expect(abs(tb.nodes["A"]!.midX - tb.nodes["C"]!.midX) < 0.5)
        let lr = LayeredLayout.compute(graph([("A", "B")], direction: .leftToRight))
        #expect(lr.nodes["A"]!.midX < lr.nodes["B"]!.midX)
        let bt = LayeredLayout.compute(graph([("A", "B")], direction: .bottomToTop))
        #expect(bt.nodes["A"]!.midY > bt.nodes["B"]!.midY)
        let rl = LayeredLayout.compute(graph([("A", "B")], direction: .rightToLeft))
        #expect(rl.nodes["A"]!.midX > rl.nodes["B"]!.midX)
    }

    @Test func contentStartsAtOriginAndFitsSize() {
        let layout = LayeredLayout.compute(graph([("A", "B"), ("A", "C"), ("B", "D"), ("C", "D")]))
        let all = layout.nodes.values.reduce(layout.nodes.values.first!) { $0.union($1) }
        #expect(abs(all.minX) < 0.001 && abs(all.minY) < 0.001)
        #expect(all.maxX <= layout.size.width + 0.001 && all.maxY <= layout.size.height + 0.001)
        assertNoOverlaps(layout)
    }

    @Test func cyclesStillLayOutAndRouteInOriginalDirection() {
        let layout = LayeredLayout.compute(graph([("A", "B"), ("B", "C"), ("C", "A")]))
        assertNoOverlaps(layout)
        let back = layout.edges[2].points
        #expect(back.first == layout.nodes["C"]!.center)
        #expect(back.last == layout.nodes["A"]!.center)
    }

    @Test func longEdgesPassVerticallyThroughIntermediateRanks() {
        let layout = LayeredLayout.compute(graph([("A", "B"), ("B", "C"), ("A", "C")]))
        let points = layout.edges[2].points
        #expect(points.count == 4)
        // The bend occupies B's rank band from top to bottom at one x, so the
        // edge cannot cut through B's neighbors.
        #expect(points[1].x == points[2].x)
        #expect(points[1].y <= layout.nodes["B"]!.minY + 0.001)
        #expect(points[2].y >= layout.nodes["B"]!.maxY - 0.001)
        #expect(abs(points[1].x - layout.nodes["B"]!.midX) >= layout.nodes["B"]!.width / 2)
    }

    @Test func labeledEdgesGetALabelSlot() {
        var g = graph([("A", "B")])
        g.edges[0].labelSize = Size(40, 16)
        let layout = LayeredLayout.compute(g)
        let label = try! #require(layout.edges[0].labelCenter)
        #expect(label.y > layout.nodes["A"]!.maxY && label.y < layout.nodes["B"]!.minY)
    }

    @Test func clustersContainMembersAndExcludeOthers() {
        let g = graph([("A", "B"), ("B", "C"), ("X", "C"), ("A", "X")],
                      clusters: [.init(id: "S", labelSize: Size(80, 18))], membership: ["A": "S", "B": "S"])
        let layout = LayeredLayout.compute(g)
        let box = try! #require(layout.clusters["S"])
        #expect(box.contains(layout.nodes["A"]!.center) && box.contains(layout.nodes["B"]!.center))
        #expect(!box.intersects(layout.nodes["X"]!))
        #expect(!box.intersects(layout.nodes["C"]!))
        #expect(layout.nodes["A"]!.minY - box.minY >= 18)
        assertNoOverlaps(layout)
    }

    @Test func nestedClustersNestAndSiblingsDoNotOverlap() {
        let g = graph([("A", "B"), ("C", "D"), ("B", "D")],
                      clusters: [.init(id: "outer"), .init(id: "inner", parent: "outer"), .init(id: "other")],
                      membership: ["A": "inner", "B": "outer", "C": "other", "D": "other"])
        let layout = LayeredLayout.compute(g)
        let outer = layout.clusters["outer"]!, inner = layout.clusters["inner"]!, other = layout.clusters["other"]!
        #expect(outer.contains(inner.origin) && outer.contains(Point(inner.maxX, inner.maxY)))
        #expect(!outer.intersects(other))
    }

    @Test func edgesToClustersAndEmptyClusters() {
        let g = graph([("A", "S"), ("A", "E")], clusters: [.init(id: "S"), .init(id: "E")], membership: ["B": "S"])
        let layout = LayeredLayout.compute(g)
        #expect(layout.clusters["E"] != nil)
        #expect(layout.edges[0].points.count >= 2)
        #expect(layout.edges[1].points.count >= 2)
    }

    @Test func selfLoopsRouteBesideTheNode() {
        let layout = LayeredLayout.compute(graph([("A", "A")]))
        let points = layout.edges[0].points
        #expect(points.count == 4)
        #expect(points[1].x > layout.nodes["A"]!.maxX)
    }
}
