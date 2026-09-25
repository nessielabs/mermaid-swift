import Testing
@testable import Mermaid

@Suite("Sankey layout")
struct SankeyLayoutTests {
    /// A small energy-style network with merges, splits and a long link.
    static let network: [(Int, Int, Double)] = [
        (0, 2, 124.7), (1, 2, 4.4), (2, 3, 280.3), (2, 4, 26.9), (5, 3, 35), (3, 6, 400.1), (3, 4, 20),
        (6, 4, 787.1), (6, 7, 525.5), (7, 8, 342.2), (7, 4, 56.7), (0, 8, 30), (9, 6, 839.9),
    ]

    func layout(_ links: [(Int, Int, Double)] = network, nodes: Int = 10, alignment: SankeyLayout.Alignment = .justify,
                size: Size = Size(600, 400)) -> SankeyLayout {
        var layout = SankeyLayout(nodeCount: nodes, links: links.map { ($0.0, $0.1, $0.2) },
                                  extent: Rect(x: 0, y: 0, width: size.width, height: size.height),
                                  nodeWidth: 10, nodePadding: 12, alignment: alignment)
        layout.compute()
        return layout
    }

    @Test func flowIsConservedThroughEveryNode() {
        let l = layout()
        let scale = l.nodes[0].frame.height / l.nodes[0].value
        for (i, node) in l.nodes.enumerated() {
            let inflow = l.links.filter { $0.target == i }.reduce(0) { $0 + $1.value }
            let outflow = l.links.filter { $0.source == i }.reduce(0) { $0 + $1.value }
            #expect(abs(node.value - max(inflow, outflow)) < 1e-9)
            // One value-to-height scale for every node and link.
            #expect(abs(node.frame.height - node.value * scale) < 1e-6)
            let inWidth = l.links.filter { $0.target == i }.reduce(0) { $0 + $1.width }
            let outWidth = l.links.filter { $0.source == i }.reduce(0) { $0 + $1.width }
            #expect(inWidth <= node.frame.height + 1e-6 && outWidth <= node.frame.height + 1e-6)
        }
        for link in l.links { #expect(abs(link.width - link.value * scale) < 1e-6) }
    }

    @Test func nodesStayInsideTheExtentWithoutOverlapping() {
        let l = layout()
        for node in l.nodes {
            #expect(node.x0 >= -1e-6 && node.x1 <= 600 + 1e-6)
            #expect(node.y0 >= -1e-6 && node.y1 <= 400 + 1e-6)
        }
        for layer in Set(l.nodes.map(\.layer)) {
            let column = l.nodes.filter { $0.layer == layer }.sorted { $0.y0 < $1.y0 }
            for (a, b) in zip(column, column.dropFirst()) { #expect(b.y0 >= a.y1 - 1e-6) }
        }
    }

    @Test func linksStackWithinTheirNodes() {
        let l = layout()
        for (i, node) in l.nodes.enumerated() {
            let outgoing = node.sourceLinks.map { l.links[$0] }
            var y = node.y0
            for link in outgoing {
                #expect(abs(link.y0 - (y + link.width / 2)) < 1e-6)
                y += link.width
            }
            // Outgoing links are ordered by the vertical position of their targets.
            let targets = outgoing.map { l.nodes[$0.target].y0 }
            #expect(targets == targets.sorted(), "node \(i)")
            let incoming = node.targetLinks.map { l.links[$0] }
            #expect(incoming.allSatisfy { $0.y1 >= node.y0 - 1e-6 && $0.y1 <= node.y1 + 1e-6 })
        }
    }

    @Test func linksAlwaysRunLeftToRight() {
        for alignment in [SankeyLayout.Alignment.justify, .left, .right, .center] {
            let l = layout(alignment: alignment)
            for link in l.links { #expect(l.nodes[link.source].layer < l.nodes[link.target].layer, "\(alignment)") }
        }
    }

    @Test func alignmentsPlaceSourcesAndSinks() {
        // 0 → 1 → 2, and 3 → 2: node 3 is a source one step from the sink.
        let links: [(Int, Int, Double)] = [(0, 1, 5), (1, 2, 5), (3, 2, 2), (0, 4, 1)]
        let justify = layout(links, nodes: 5)
        #expect(justify.nodes.map(\.layer) == [0, 1, 2, 0, 2])
        let left = layout(links, nodes: 5, alignment: .left)
        #expect(left.nodes.map(\.layer) == [0, 1, 2, 0, 1])
        let right = layout(links, nodes: 5, alignment: .right)
        #expect(right.nodes.map(\.layer) == [0, 1, 2, 1, 2])
        let center = layout(links, nodes: 5, alignment: .center)
        #expect(center.nodes.map(\.layer) == [0, 1, 2, 1, 1])
        #expect(justify.nodes[2].x1 == 600 && justify.nodes[0].x0 == 0)
    }

    @Test func singleNodeAndZeroValuesDoNotCrash() {
        let lone = layout([(0, 1, 0)], nodes: 2)
        #expect(lone.nodes.allSatisfy { $0.y0.isFinite && $0.y1.isFinite })
        let empty = layout([], nodes: 0)
        #expect(empty.nodes.isEmpty)
    }
}
