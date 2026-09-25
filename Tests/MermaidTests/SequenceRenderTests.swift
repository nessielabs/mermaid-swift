import Testing
@testable import Mermaid

@Suite("Sequence rendering")
struct SequenceRenderTests {
    let options = RenderOptions(measurer: ApproximateTextMeasurer())

    static let tour = """
    ---
    title: Tour
    ---
    sequenceDiagram
        autonumber
        box Aqua Front
        actor U as User
        participant W as Web
        end
        participant API@{ "type": "boundary" }
        participant S@{ "type": "control" }
        participant E@{ "type": "entity" }
        participant DB@{ "type": "database" }
        participant Q@{ "type": "collections" }
        participant MQ@{ "type": "queue" }
        U->>+W: Log in
        W->>API: POST /login
        API-)S: async
        S--xDB: lost
        S<<->>Q: both ways
        Q-|\\MQ: half
        MQ//--Q: reverse stick
        W->>()API: central
        S->>S: self
        W-->>-U: ok
        Note over W,API: note
        rect rgb(200, 220, 255)
        loop poll
            alt ok
                W->>API: a
            else fail
                W->>API: b
            end
        end
        end
        create participant T
        API->>T: spawn
        destroy T
        T-->>API: bye
    """

    @Test func detectsAndRendersSequenceDiagrams() throws {
        #expect(Mermaid.detectType("sequenceDiagram\nA->>B: hi") == .sequence)
        #expect(Mermaid.supportedTypes.contains(.sequence))
        let scene = try Mermaid.render(Self.tour, options: options)
        #expect(scene.size.width > 800 && scene.size.height > 600)
        let svg = scene.svg
        for text in ["Log in", "POST /login", "Tour", "[poll]", "[fail]", "User", "spawn"] {
            #expect(svg.contains(">\(text)</text>"), "\(text)")
        }
        #expect(svg.contains("id=\"lifeline-W\""))
    }

    @Test func everythingDrawnFitsTheCanvas() throws {
        let scene = try Mermaid.render(
            "sequenceDiagram\nNote left of A: far to the left of the first participant\nA->>B: hi\nNote right of B: and far right",
            options: options)
        func points(_ item: SceneItem) -> [Point] {
            switch item {
            case .shape(let s): return s.path.bounds.map { [$0.origin, Point($0.maxX, $0.maxY)] } ?? []
            case .text(let t): return [t.frame.origin, Point(t.frame.maxX, t.frame.maxY)]
            case .group(let g): return g.items.flatMap(points)
            }
        }
        for p in scene.items.flatMap(points) {
            #expect(p.x >= 0 && p.y >= 0 && p.x <= scene.size.width && p.y <= scene.size.height)
        }
    }

    @Test func themeVariablesColorTheDiagram() throws {
        let source = """
        %%{init: {"themeVariables": {"actorBkg": "#ff0000", "noteBkgColor": "#00ff00", "signalColor": "#0000ff"}}}%%
        sequenceDiagram
        A->>B: hi
        Note over A: note
        """
        let svg = try Mermaid.render(source, options: options).svg
        #expect(svg.contains("fill=\"#ff0000\""))
        #expect(svg.contains("fill=\"#00ff00\""))
        #expect(svg.contains("stroke=\"#0000ff\""))
    }

    @Test func everyThemeRenders() throws {
        for name in Theme.Name.allCases {
            let scene = try Mermaid.render(Self.tour, options: RenderOptions(theme: Theme(name), measurer: ApproximateTextMeasurer()))
            #expect(!scene.items.isEmpty, "\(name)")
        }
    }

    @Test func malformedInputThrowsInsteadOfCrashing() {
        let inputs = [
            "sequenceDiagram\nA->>", "sequenceDiagram\n->>B: x", "sequenceDiagram\nloop", "sequenceDiagram\nend",
            "sequenceDiagram\nNote", "sequenceDiagram\nparticipant", "sequenceDiagram\nparticipant A@{",
            "sequenceDiagram\nbox\nend", "sequenceDiagram\nautonumber 1 2 3", "sequenceDiagram\ndeactivate A",
            "sequenceDiagram\nA->>B: x\nelse", "sequenceDiagram\ncreate", "sequenceDiagram\n;;;", "sequenceDiagram\n#",
        ]
        for input in inputs {
            do { _ = try Mermaid.render(input, options: options) } catch is MermaidError {} catch {
                Issue.record("\(input): unexpected \(error)")
            }
        }
    }

    @Test func emptyDiagramsRender() throws {
        let scene = try Mermaid.render("sequenceDiagram", options: options)
        #expect(scene.size.width >= 0 && scene.size.height >= 0)
    }
}
