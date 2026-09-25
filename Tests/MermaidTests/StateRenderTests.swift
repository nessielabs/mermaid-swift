import Testing
@testable import Mermaid

@Suite("State diagram rendering")
struct StateRenderTests {
    func render(_ source: String) throws -> Scene {
        try Mermaid.render(source, options: RenderOptions(measurer: ApproximateTextMeasurer()))
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

    @Test func bothHeadersAreRegistered() {
        #expect(Mermaid.detectType("stateDiagram\n  a --> b") == .state)
        #expect(Mermaid.detectType("stateDiagram-v2\n  a --> b") == .state)
        #expect(Mermaid.supportedTypes.contains(.state))
    }

    @Test func sceneDrawsEveryElement() throws {
        let scene = try render("""
        stateDiagram-v2
            [*] --> Active
            state Active {
                [*] --> On
                --
                [*] --> Off
            }
            state c <<choice>>
            Active --> c
            c --> [*] : done
            note left of c : pick
            note "floating" as N
        """)
        let byID = groups(scene.items)
        #expect(byID["Active"]?.role == "composite")
        #expect(byID["root_start"]?.role == "state-start" && byID["root_end"]?.role == "state-end")
        #expect(byID["c"]?.role == "state-choice")
        #expect(byID["N"]?.role == "note")
        #expect(byID.keys.contains { $0.hasPrefix("transition-") })
        #expect(scene.svg.contains(">done</text>"))
        // The canvas fits the content with the diagram padding around it.
        let bounds = try #require(SceneItem.bounds(of: scene.items))
        #expect(bounds.minX >= 7.9 && bounds.maxX <= scene.size.width - 7.9)
    }

    @Test func transitionsStopAtTheirTargetsOutline() throws {
        let scene = try render("stateDiagram-v2\na --> b")
        let edge = try #require(groups(scene.items)["transition-0"])
        let b = try #require(groups(scene.items)["b"].flatMap { SceneItem.group($0).bounds })
        guard case .shape(let arrow)? = edge.items.dropFirst().first, let tip = arrow.path.bounds else {
            Issue.record("missing arrowhead")
            return
        }
        #expect(abs(tip.maxY - b.minY) < 1.5)
    }

    @Test func malformedInputNeverCrashes() {
        let seeds = [
            "state A {\n a --> b\n --\n c\n}", "note right of X\n text\nend note", "s1 : a\ns1 --> [*] : x",
            "state \"d\" as e {\n [*] --> f\n}", "classDef c fill:#f00\nclass a c\nstyle a stroke:red",
        ]
        let noise = ["{", "}", "--", "-->", ":", ":::", "\"", "[*]", "<<fork>>", "note", "state", "\n", " ", "%%"]
        var generator = SystemRandomNumberGenerator()
        for seed in seeds {
            for _ in 0..<60 {
                var text = Array(seed)
                for _ in 0..<3 {
                    let insert = Array(noise.randomElement(using: &generator)!)
                    text.insert(contentsOf: insert, at: Int.random(in: 0...text.count, using: &generator))
                }
                let source = "stateDiagram-v2\n" + String(text)
                do {
                    _ = try render(source)
                } catch is MermaidError {
                    // Located errors are the expected outcome for broken input.
                } catch {
                    Issue.record("unexpected error for \(source): \(error)")
                }
            }
        }
    }
}
