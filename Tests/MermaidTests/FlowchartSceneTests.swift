import Testing
@testable import Mermaid

@Suite("Flowchart scenes")
struct FlowchartSceneTests {
    let options = RenderOptions(measurer: ApproximateTextMeasurer())

    func groups(_ items: [SceneItem], role: String) -> [GroupItem] {
        items.flatMap { item -> [GroupItem] in
            guard case .group(let group) = item else { return [] }
            return (group.role == role ? [group] : []) + groups(group.items, role: role)
        }
    }

    func bounds(_ items: [SceneItem]) -> Rect? {
        let rects = items.compactMap { item -> Rect? in
            switch item {
            case .shape(let shape): return shape.path.bounds
            case .text(let text): return text.frame
            case .group(let group): return bounds(group.items)
            }
        }
        guard var result = rects.first else { return nil }
        for r in rects.dropFirst() { result = result.union(r) }
        return result
    }

    let source = """
    ---
    title: Order pipeline
    ---
    flowchart LR
      subgraph Intake
        A[Receive order] --> B{Valid?}
      end
      subgraph Fulfil[Fulfilment]
        direction TB
        C[(Inventory)] --> D([Ship])
      end
      B -->|yes| C
      B -- no --> E>Reject]
      D -.-> F((Done))
      E ==> F
    """

    @Test func everythingFitsTheCanvas() throws {
        let scene = try Mermaid.render(source, options: options)
        let content = try #require(bounds(scene.items))
        #expect(content.minX >= -0.5 && content.minY >= -0.5)
        #expect(content.maxX <= scene.size.width + 0.5 && content.maxY <= scene.size.height + 0.5)
        #expect(scene.accessibilityTitle == "Order pipeline")
    }

    @Test func labelsSitInsideTheirNodes() throws {
        let scene = try Mermaid.render(source, options: options)
        let nodes = groups(scene.items, role: "node")
        #expect(nodes.count == 6)
        for node in nodes {
            let body = try #require(bounds(node.items.filter { if case .shape = $0 { true } else { false } }))
            for case .text(let text) in node.items {
                #expect(body.insetBy(dx: -0.5, dy: -0.5).contains(text.frame.origin), "\(node.id ?? "")")
                #expect(body.insetBy(dx: -0.5, dy: -0.5).contains(Point(text.frame.maxX, text.frame.maxY)), "\(node.id ?? "")")
            }
        }
    }

    @Test func clustersContainTheirMembers() throws {
        let scene = try Mermaid.render(source, options: options)
        let clusters = Dictionary(uniqueKeysWithValues: groups(scene.items, role: "cluster").map { ($0.id!, bounds($0.items)!) })
        let nodes = Dictionary(uniqueKeysWithValues: groups(scene.items, role: "node").map { ($0.id!, bounds($0.items)!) })
        for (cluster, members) in [("Intake", ["A", "B"]), ("Fulfil", ["C", "D"])] {
            for member in members {
                #expect(clusters[cluster]!.contains(nodes[member]!.center), "\(member) in \(cluster)")
            }
        }
        #expect(!clusters["Intake"]!.intersects(clusters["Fulfil"]!))
    }

    @Test func edgesStartAndEndOnTheirNodes() throws {
        let scene = try Mermaid.render("flowchart TD\n  A[Start] --> B{Decide}\n  B --> C((Stop))", options: options)
        let nodes = Dictionary(uniqueKeysWithValues: groups(scene.items, role: "node").map { ($0.id!, bounds($0.items)!) })
        for edge in groups(scene.items, role: "edge") {
            guard case .shape(let line)? = edge.items.first, let first = line.path.elements.first,
                  case .move(let start) = first else { Issue.record("edge without a line"); continue }
            let near = nodes.values.contains { $0.insetBy(dx: -2, dy: -2).contains(start) }
            #expect(near, "edge starts away from every node")
        }
    }

    @Test func invisibleLinksAffectLayoutButAreNotDrawn() throws {
        let scene = try Mermaid.render("flowchart LR\n  A ~~~ B", options: options)
        #expect(groups(scene.items, role: "edge").isEmpty)
        #expect(groups(scene.items, role: "node").count == 2)
    }

    @Test func classDefinitionsColorNodes() throws {
        let scene = try Mermaid.render("flowchart LR\n  A:::hot\n  classDef hot fill:#ff0000", options: options)
        let node = try #require(groups(scene.items, role: "node").first)
        guard case .shape(let body)? = node.items.first else { Issue.record("no body"); return }
        #expect(body.fill == Color(hex: 0xFF0000))
    }

    @Test func darkThemeRecolorsDefaults() throws {
        let scene = try Mermaid.render("%%{init: {'theme': 'dark'}}%%\nflowchart LR\n  A", options: options)
        #expect(scene.background == Theme.dark.background)
    }
}
