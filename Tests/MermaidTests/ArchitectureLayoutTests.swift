import Testing
@testable import Mermaid

@Suite("Architecture layout and rendering")
struct ArchitectureLayoutTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func builder(_ source: String) throws -> ArchitectureSceneBuilder {
        let diagram = try #require(try Mermaid.parse(source).diagram as? ArchitectureDiagram)
        return ArchitectureSceneBuilder(diagram: diagram, context: context)
    }

    /// Lays out with fixed 80×100 services whose icon center is 40 below the top.
    func layout(_ source: String) throws -> (ArchitectureDiagram, ArchitectureLayout) {
        let d = try #require(try Mermaid.parse(source).diagram as? ArchitectureDiagram)
        var sizes: [String: Size] = [:], anchors: [String: Point] = [:]
        for node in d.nodes {
            sizes[node.id] = node.kind == .junction ? Size(12, 12) : Size(80, 100)
            anchors[node.id] = node.kind == .junction ? Point(6, 6) : Point(40, 40)
        }
        let headers = Dictionary(uniqueKeysWithValues: d.groups.map { ($0.id, Size(80, 30)) })
        let input = ArchitectureLayout.Input(nodeSizes: sizes, nodeAnchors: anchors, groupHeaders: headers,
                                             edgeLabels: [:], gap: 60, groupPadding: 30)
        return (d, ArchitectureLayout.compute(d, input))
    }

    func iconCenter(_ layout: ArchitectureLayout, _ id: String) throws -> Point {
        let frame = try #require(layout.nodes[id])
        return Point(frame.midX, frame.minY + 40)
    }

    @Test func edgeSidesPlaceNeighbors() throws {
        let (_, l) = try layout("""
        architecture-beta
        service a[A]
        service r[R]
        service lft[L]
        service t[T]
        service b[B]
        a:R -- L:r
        a:L -- R:lft
        a:T -- B:t
        a:B -- T:b
        """)
        let a = try iconCenter(l, "a")
        let r = try iconCenter(l, "r"), lft = try iconCenter(l, "lft"), t = try iconCenter(l, "t"), b = try iconCenter(l, "b")
        #expect(r.x > a.x && r.y == a.y)
        #expect(lft.x < a.x && lft.y == a.y)
        #expect(t.y < a.y && t.x == a.x)
        #expect(b.y > a.y && b.x == a.x)
    }

    @Test func perpendicularSidesPlaceDiagonally() throws {
        let (_, l) = try layout("""
        architecture-beta
        service a[A]
        service b[B]
        service c[C]
        a:T -- L:b
        a:R -- T:c
        """)
        let a = try iconCenter(l, "a"), b = try iconCenter(l, "b"), c = try iconCenter(l, "c")
        #expect(b.x > a.x && b.y < a.y)
        #expect(c.x > a.x && c.y > a.y)
    }

    @Test func crowdedSidesNeverOverlap() throws {
        let (d, l) = try layout("""
        architecture-beta
        service hub[Hub]
        service a[A]
        service b[B]
        service c[C]
        service lonely[Lonely]
        hub:R -- L:a
        hub:R -- L:b
        hub:R -- L:c
        """)
        let frames = d.nodes.compactMap { l.nodes[$0.id] }
        #expect(frames.count == 5)
        for i in frames.indices { for j in frames.indices where i < j { #expect(!frames[i].intersects(frames[j])) } }
        for id in ["a", "b", "c"] { #expect(try iconCenter(l, id).x > iconCenter(l, "hub").x) }
    }

    @Test func groupsContainMembersAndDoNotOverlap() throws {
        let (d, l) = try layout("""
        architecture-beta
        group outer(cloud)[Outer]
        group inner(database)[Inner] in outer
        group other[Other]
        service a[A] in inner
        service b[B] in inner
        service c[C] in outer
        service x[X] in other
        service y[Y]
        a:R -- L:b
        c:B -- T:a
        c{group}:R -- L:x{group}
        y:T -- B:c
        """)
        for node in d.nodes {
            let frame = try #require(l.nodes[node.id])
            var parent = node.parent
            while let group = parent {
                let box = try #require(l.groups[group])
                #expect(box.contains(frame.origin) && box.contains(Point(frame.maxX, frame.maxY)), "\(node.id) in \(group)")
                parent = d.group(group)?.parent
            }
        }
        let outer = try #require(l.groups["outer"]), other = try #require(l.groups["other"])
        #expect(!outer.intersects(other))
        // The {group} edge puts the other group to the right of outer.
        #expect(other.minX > outer.maxX)
        let frames = d.nodes.compactMap { l.nodes[$0.id] }
        for i in frames.indices { for j in frames.indices where i < j { #expect(!frames[i].intersects(frames[j])) } }
    }

    @Test func alignmentDirectives() throws {
        let (_, l) = try layout("""
        architecture-beta
        service a[A]
        service b[B]
        service c[C]
        service m[M]
        a:R -- L:m
        b:R -- L:m
        c:R -- L:m
        align column a b c
        """)
        let a = try iconCenter(l, "a"), b = try iconCenter(l, "b"), c = try iconCenter(l, "c")
        #expect(a.x == b.x && b.x == c.x && a.y < b.y && b.y < c.y)
        let (_, rowLayout) = try layout("""
        architecture-beta
        service a[A]
        service b[B]
        service p[P]
        a:B -- T:p
        b:B -- T:p
        align row a b
        """)
        let ra = try iconCenter(rowLayout, "a"), rb = try iconCenter(rowLayout, "b")
        #expect(ra.y == rb.y && ra.x < rb.x)
    }

    @Test func disconnectedPartsSitSideBySide() throws {
        let (_, l) = try layout("""
        architecture-beta
        service a[A]
        service b[B]
        service c[C]
        a:B -- T:b
        """)
        let c = try #require(l.nodes["c"])
        #expect(c.minX > max(l.nodes["a"]!.maxX, l.nodes["b"]!.maxX))
    }

    @Test func routesLeaveAndEnterThroughTheirSides() throws {
        let b = try builder("""
        architecture-beta
        service a(server)[A]
        service c(disk)[C]
        service d(database)[D]
        junction j
        a:R --> L:c
        a:T -- L:d
        c:B -- T:j
        """)
        let layout = try #require(Optional(ArchitectureLayout.compute(b.diagram, ArchitectureLayout.Input(
            nodeSizes: Dictionary(uniqueKeysWithValues: b.diagram.nodes.map { ($0.id, $0.kind == .junction ? Size(12, 12) : Size(80, 100)) }),
            nodeAnchors: Dictionary(uniqueKeysWithValues: b.diagram.nodes.map { ($0.id, $0.kind == .junction ? Point(6, 6) : Point(40, 40)) }),
            groupHeaders: [:], edgeLabels: [:], gap: 60, groupPadding: 30))))
        let router = ArchitectureEdgeRouter(diagram: b.diagram, layout: layout, iconSize: 80, titles: [:])
        for edge in b.diagram.edges {
            let route = router.route(edge)
            #expect(route.count >= 2)
            // Orthogonal segments only.
            for (p, q) in zip(route, route.dropFirst()) { #expect(abs(p.x - q.x) < 0.01 || abs(p.y - q.y) < 0.01) }
            // The first segment heads out of the source's side, the last into the target's.
            let first = (route[1] - route[0]).normalized, last = (route[route.count - 2] - route[route.count - 1]).normalized
            #expect(first.distance(to: edge.fromSide.outward) < 0.01, "\(edge.from)")
            #expect(last.distance(to: edge.toSide.outward) < 0.01, "\(edge.to)")
        }
        let straight = router.route(b.diagram.edges[0])
        #expect(straight.count == 2)
        let elbow = router.route(b.diagram.edges[1])
        #expect(elbow.count == 3)
    }

    @Test func routerConnectsEveryShape() {
        let a = Point(0, 0)
        for sa in ArchitectureDiagram.Side.allCases {
            for sb in ArchitectureDiagram.Side.allCases {
                for b in [Point(200, 0), Point(-200, 50), Point(30, 200), Point(-150, -150)] {
                    let route = ArchitectureEdgeRouter.simplify(ArchitectureEdgeRouter.connect(a, sa, b, sb))
                    #expect(route.first == a && route.last == b)
                    for (p, q) in zip(route, route.dropFirst()) { #expect(abs(p.x - q.x) < 0.01 || abs(p.y - q.y) < 0.01) }
                }
            }
        }
    }

    @Test func sceneDrawsGroupsServicesEdgesAndLabels() throws {
        let scene = try Mermaid.render("""
        architecture-beta
        title Platform
        group api(cloud)[API]
        service db(database)[Database] in api
        service server(server)[Server] in api
        service pay(logos:stripe)[Payments]
        service text "Hi there"[Text]
        db:L -[queries]- R:server
        server:T --> B:pay
        """, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        let svg = scene.svg
        for needle in ["id=\"api\"", "id=\"db\"", "id=\"server\"", "id=\"L_db_server_0\"", ">queries<", ">Platform<", ">?<", ">Hi there<"] {
            #expect(svg.contains(needle), "\(needle)")
        }
        #expect(svg.contains("#087ebf"))
        #expect(Mermaid.detectType("architecture\nservice a[A]") == .architecture)
    }

    @Test func verticalLabelsRunAlongTheirEdge() throws {
        let b = try builder("architecture-beta\nservice a[A]\nservice b[B]\na:B -[down]- T:b")
        let label = b.text("down")
        guard case .group(let group) = b.labelItem(label, on: [Point(0, 0), Point(0, 200)], id: "x"),
              case .text(let text)? = group.items.last else { Issue.record("no label"); return }
        #expect(text.rotation == -90)
    }
}
