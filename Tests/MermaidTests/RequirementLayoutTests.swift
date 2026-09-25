import Testing
@testable import Mermaid

@Suite("Requirement layout")
struct RequirementLayoutTests {
    let options = RenderOptions(measurer: ApproximateTextMeasurer())

    func render(_ source: String) throws -> Scene { try Mermaid.render(source, options: options) }

    func groups(_ scene: Scene, roles: Set<String>) -> [String: GroupItem] {
        var result: [String: GroupItem] = [:]
        for case .group(let group) in scene.items where roles.contains(group.role ?? "") { result[group.id ?? ""] = group }
        return result
    }

    func frame(_ group: GroupItem) -> Rect? {
        guard case .shape(let shape)? = group.items.first else { return nil }
        return shape.path.bounds
    }

    let sample = """
    requirementDiagram
        requirement test_req {
            id: 1
            text: the test text.
            risk: high
            verifymethod: test
        }
        functionalRequirement test_req2 {
            id: 1.1
            text: a much longer requirement text that should wrap onto several lines instead of stretching the box
        }
        element test_entity {
            type: simulation
        }
        test_entity - satisfies -> test_req2
        test_req - contains -> test_req2
        test_req - traces -> ghost
    """

    @Test func registeredAndDetected() throws {
        #expect(Mermaid.detectType("requirementDiagram\n") == .requirement)
        #expect(try Mermaid.parse(sample).type == .requirement)
    }

    @Test func nodesDoNotOverlapAndUndeclaredNamesAppear() throws {
        let scene = try render(sample)
        let nodes = groups(scene, roles: ["requirement", "element"]).compactMapValues(frame)
        #expect(Set(nodes.keys) == ["test_req", "test_req2", "test_entity", "ghost"])
        let frames = Array(nodes.values)
        for i in frames.indices {
            for j in (i + 1)..<frames.count { #expect(!frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j])) }
        }
        for f in frames { #expect(f.maxX <= scene.size.width && f.maxY <= scene.size.height) }
    }

    @Test func textStaysInsideBoxesAndWraps() throws {
        let scene = try render(sample)
        for (id, group) in groups(scene, roles: ["requirement", "element"]) {
            let box = try #require(frame(group))
            for case .text(let text) in group.items {
                #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(text.frame.origin), "\(id)")
                #expect(text.frame.maxX <= box.maxX + 0.5 && text.frame.maxY <= box.maxY + 0.5, "\(id)")
            }
        }
        let long = try #require(groups(scene, roles: ["requirement"])["test_req2"])
        let wrapped = long.items.contains { item in
            if case .text(let text) = item { return text.block.lines.count > 1 }
            return false
        }
        #expect(wrapped)
        #expect(try #require(frame(long)).width <= RequirementSceneBuilder.bodyWrapWidth + 2 * RequirementBox.padding.width + 1)
    }

    @Test func relationshipStylesAndLabels() throws {
        let scene = try render(sample)
        let edges = groups(scene, roles: ["relationship"])
        #expect(edges.count == 3)
        func line(_ id: String) -> ShapeItem? {
            guard case .group(let connector)? = edges[id]?.items.first, case .shape(let shape)? = connector.items.first
            else { return nil }
            return shape
        }
        #expect(line("test_req-test_req2-1")?.stroke?.dash == [])
        #expect(line("test_entity-test_req2-0")?.stroke?.dash == [10, 7])
        let labels = edges.values.flatMap { group -> [String] in
            guard case .group(let connector)? = group.items.first else { return [] }
            return connector.items.compactMap { item in
                if case .text(let text) = item { return text.block.lines.first?.runs.first?.text }
                return nil
            }
        }
        #expect(Set(labels) == ["<<satisfies>>", "<<contains>>", "<<traces>>"])
    }

    @Test func boxWithoutFieldsHasNoDivider() {
        let context = RenderContext(measurer: ApproximateTextMeasurer())
        let builder = RequirementSceneBuilder(diagram: .init(), context: context)
        let bare = builder.box(stereotype: "Element", name: "x", fields: [("Type", "")], style: ElementStyle())
        let full = builder.box(stereotype: "Element", name: "x", fields: [("Type", "db")], style: ElementStyle())
        #expect(bare.body.isEmpty && full.body.count == 1)
        #expect(full.size.height > bare.size.height + RequirementBox.gap)
    }

    @Test func directionIsHonored() throws {
        let scene = try render("requirementDiagram\ndirection LR\nelement a {\n}\nelement b {\n}\na - traces -> b")
        let nodes = groups(scene, roles: ["element"]).compactMapValues(frame)
        #expect(try #require(nodes["a"]).maxX < (try #require(nodes["b"])).minX)
    }

    @Test func malformedInputNeverCrashes() {
        for input in ["requirementDiagram\n{", "requirementDiagram\nrequirement {", "requirementDiagram\n- ->",
                      "requirementDiagram\na <- -", "requirementDiagram\n\"a - satisfies -> b", "requirementDiagram\n}",
                      "requirementDiagram\nelement e {\n}}", "requirementDiagram\n:::", "requirementDiagram\nstyle"] {
            do { _ = try render(input) } catch is MermaidError {} catch { Issue.record("\(input): \(error)") }
        }
    }
}
