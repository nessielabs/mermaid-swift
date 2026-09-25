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
        // center, exit port, bend entry, bend exit, entry port, center
        #expect(points.count == 6)
        // The bend occupies B's rank band from top to bottom at one x, so the
        // edge cannot cut through B's neighbors.
        #expect(points[2].x == points[3].x)
        #expect(points[2].y <= layout.nodes["B"]!.minY + 0.001)
        #expect(points[3].y >= layout.nodes["B"]!.maxY - 0.001)
        #expect(abs(points[2].x - layout.nodes["B"]!.midX) >= layout.nodes["B"]!.width / 2)
    }

    @Test func edgesLeaveAndEnterThroughSpreadPorts() {
        let layout = LayeredLayout.compute(graph([("A", "B"), ("A", "C"), ("A", "D")]))
        let a = layout.nodes["A"]!
        let exits = layout.edges.map { $0.points[1] }
        #expect(exits.allSatisfy { abs($0.y - a.maxY) < 0.001 && $0.x > a.minX && $0.x < a.maxX })
        #expect(Set(exits.map(\.x)).count == 3)
        // Ports follow the targets' left-to-right order, so edges do not cross.
        let targets = ["B", "C", "D"].map { layout.nodes[$0]!.midX }
        #expect(zip(exits, targets).sorted { $0.1 < $1.1 }.map(\.0.x) == exits.map(\.x).sorted())
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

    @Test func isolatedClustersUseTheirOwnDirection() {
        var g = graph([("A", "B"), ("B", "C"), ("X", "Y")],
                      clusters: [.init(id: "S", labelSize: Size(40, 16), direction: .leftToRight)],
                      membership: ["A": "S", "B": "S", "C": "S"])
        g.direction = .topToBottom
        let layout = LayeredLayout.compute(g)
        let a = layout.nodes["A"]!, b = layout.nodes["B"]!, c = layout.nodes["C"]!
        #expect(a.midX < b.midX && b.midX < c.midX)
        #expect(abs(a.midY - c.midY) < 0.5)
        let box = layout.clusters["S"]!
        #expect([a, b, c].allSatisfy { box.contains($0.origin) && box.contains(Point($0.maxX, $0.maxY)) })
        #expect(layout.edges[0].points.first == a.center)
        #expect(layout.nodes["X"]!.midY < layout.nodes["Y"]!.midY)
        assertNoOverlaps(layout)
    }

    @Test func clusterDirectionIsIgnoredWhenEdgesCrossItsBoundary() {
        let g = graph([("A", "B"), ("B", "X")],
                      clusters: [.init(id: "S", direction: .leftToRight)], membership: ["A": "S", "B": "S"])
        let layout = LayeredLayout.compute(g)
        #expect(layout.nodes["A"]!.midY < layout.nodes["B"]!.midY)
    }

    @Test func edgesToACollapsedClusterAttachToItsBox() {
        let g = graph([("A", "B"), ("X", "S")],
                      clusters: [.init(id: "S", direction: .leftToRight)], membership: ["A": "S", "B": "S"])
        let layout = LayeredLayout.compute(g)
        #expect(layout.edges[1].points.last == layout.clusters["S"]!.center)
    }

    @Test func longEdgesPassingAClusterStayOnOneSide() {
        // A long edge beside a cluster used to zig-zag from one side of each
        // rank to the other, drawing loops.
        var g = graph([("L", "M"), ("M", "A"), ("M", "B"), ("A", "S"), ("B", "S"),
                       ("C3", "K"), ("K", "H"), ("H", "R"), ("L", "R")],
                      clusters: [.init(id: "S", labelSize: Size(120, 16))],
                      membership: ["C1": "S", "C2": "S", "C3": "S"])
        g.edges += [.init(from: "C1", to: "C2"), .init(from: "C2", to: "C3")]
        let layout = LayeredLayout.compute(g)
        let box = layout.clusters["S"]!
        let route = layout.edges[8].points.dropFirst().dropLast()
        let sides = route.filter { $0.y > box.minY && $0.y < box.maxY }.map { $0.x < box.midX }
        #expect(!sides.isEmpty)
        #expect(Set(sides).count == 1, "long edge switches sides of the cluster")
        #expect(route.allSatisfy { !box.contains($0) })
    }

    @Test func longEdgeBendsLineUpInOneColumn() {
        // Relaxation left a long edge's bends a few points apart, and the
        // smoothed curve through those jogs wobbled. Where nothing forces a
        // jog, every bend of the edge shares one x.
        var g = graph([("L", "M"), ("M", "A"), ("M", "B"), ("A", "S"), ("B", "S"),
                       ("C3", "K"), ("K", "H"), ("H", "R"), ("L", "R")],
                      clusters: [.init(id: "S", labelSize: Size(120, 16))],
                      membership: ["C1": "S", "C2": "S", "C3": "S"])
        g.edges += [.init(from: "C1", to: "C2"), .init(from: "C2", to: "C3")]
        let layout = LayeredLayout.compute(g)
        let bends = layout.edges[8].points.dropFirst(2).dropLast(2)
        #expect(bends.count >= 6)
        #expect(Set(bends.map { ($0.x * 100).rounded() }).count == 1)
    }

    @Test func gapsGrowWhenEdgesTravelFarSideways() {
        // A root fanning out to many children forces long sideways moves in
        // the gap below it; that gap grows so the edges are not near-flat.
        let children = (1...8).map { "C\($0)" }
        let wide = LayeredLayout.compute(graph(children.map { ("R", $0) }))
        let narrow = LayeredLayout.compute(graph([("R", "C1")]))
        let gap = { (layout: LayeredLayout) in layout.nodes["C1"]!.minY - layout.nodes["R"]!.maxY }
        #expect(gap(wide) > gap(narrow) + 10)
    }

    @Test func edgesRunStraightThroughTheirLabels() {
        // The route keeps its bends' shared column through a label when that
        // column crosses the label, instead of jogging to the label's center.
        #expect(LayeredComputation.lineX(throughLabelAt: 200, width: 180, neighborColumns: [150, 150]) == 150)
        #expect(LayeredComputation.lineX(throughLabelAt: 200, width: 180, neighborColumns: [150]) == 150)
        // Outside the label (with a margin), or with neighbors in different
        // columns, the route goes through the label's center.
        #expect(LayeredComputation.lineX(throughLabelAt: 200, width: 180, neighborColumns: [100]) == 200)
        #expect(LayeredComputation.lineX(throughLabelAt: 200, width: 180, neighborColumns: [150, 170]) == 200)
        #expect(LayeredComputation.lineX(throughLabelAt: 200, width: 180, neighborColumns: []) == 200)
    }
}
