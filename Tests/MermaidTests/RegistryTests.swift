import Testing
@testable import Mermaid

@Suite("Diagram registry")
struct RegistryTests {
    @Test func everyDiagramTypeIsSupported() {
        #expect(Set(Mermaid.supportedTypes) == Set(DiagramType.allCases))
    }

    @Test(arguments: [
        ("flowchart LR\n A-->B", DiagramType.flowchart), ("graph TD\n A", .flowchart),
        ("sequenceDiagram\n A->>B: hi", .sequence), ("classDiagram\n class A", .classDiagram),
        ("stateDiagram-v2\n [*] --> A", .state), ("erDiagram\n A ||--o{ B : has", .entityRelationship),
        ("gantt\n title T\n section S\n Task :a1, 2024-01-01, 3d", .gantt), ("pie\n \"A\" : 1", .pie),
        ("journey\n section S\n Task: 5: Me", .journey), ("gitGraph\n commit", .gitGraph),
        ("mindmap\n root", .mindmap), ("timeline\n 2024 : Event", .timeline),
        ("quadrantChart\n Point A: [0.3, 0.6]", .quadrantChart), ("xychart-beta\n bar [1, 2]", .xyChart),
        ("sankey-beta\n A,B,1", .sankey), ("requirementDiagram\n requirement r {\n id: 1\n }", .requirement),
        ("C4Context\n Person(a, \"A\")", .c4), ("block-beta\n a b", .block),
        ("packet-beta\n 0-7: \"A\"", .packet), ("kanban\n Todo\n  Task", .kanban),
        ("architecture-beta\n service a(server)[A]", .architecture),
        ("radar-beta\n axis a, b, c\n curve x{1, 2, 3}", .radar), ("treemap-beta\n \"A\": 1", .treemap),
    ])
    func minimalDiagramsRender(source: String, type: DiagramType) throws {
        let diagram = try Mermaid.parse(source)
        #expect(diagram.type == type)
        let scene = try diagram.scene(options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(scene.size.width > 0 && scene.size.height > 0)
        #expect(!scene.svg.isEmpty)
    }

    @Test func unknownTypesAreLocatedErrors() {
        #expect(throws: MermaidError.self) { try Mermaid.parse("notADiagram\n A") }
        #expect(throws: MermaidError.self) { try Mermaid.parse("%% only a comment") }
    }
}
