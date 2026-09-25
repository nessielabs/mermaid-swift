import Testing
@testable import Mermaid

@Suite("Flowchart parsing")
struct FlowchartParserTests {
    func parse(_ body: String, header: String = "flowchart TD") throws -> FlowchartDiagram {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try FlowchartParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func headerDirections() throws {
        #expect(try parse("A", header: "graph LR").direction == .leftToRight)
        #expect(try parse("A", header: "flowchart BT;").direction == .bottomToTop)
        #expect(throws: MermaidError.self) { try parse("A", header: "flowchart XY") }
    }

    @Test func classicShapes() throws {
        let cases: [(String, NodeShape, String)] = [
            ("A[Rect]", .rect, "Rect"), ("A(Round)", .rounded, "Round"), ("A([Stadium])", .stadium, "Stadium"),
            ("A[[Sub]]", .subroutine, "Sub"), ("A[(DB)]", .cylinder, "DB"), ("A((C))", .circle, "C"),
            ("A(((D)))", .doubleCircle, "D"), ("A>Odd]", .asymmetric, "Odd"), ("A{Q?}", .diamond, "Q?"),
            ("A{{Hex}}", .hexagon, "Hex"), ("A[/In/]", .leanRight, "In"), ("A[\\Out\\]", .leanLeft, "Out"),
            ("A[/Trap\\]", .trapezoid, "Trap"), ("A[\\Inv/]", .invertedTrapezoid, "Inv"),
        ]
        for (source, shape, label) in cases {
            let node = try #require(try parse(source).nodes.first)
            #expect(node.shape == shape, "\(source)")
            #expect(node.label == label, "\(source)")
        }
    }

    @Test func quotedLabelsMayContainDelimiters() throws {
        let node = try parse(#"A["Hello [world] (x)"] --> B"#).nodes[0]
        #expect(node.label == "Hello [world] (x)")
    }

    @Test func quotedStringsMayStandInForNodeIDs() throws {
        let d = try parse(#""Mac SQLite" --> "Sync API""#)
        #expect(d.nodes.map(\.id) == ["Mac SQLite", "Sync API"])
        #expect(d.links.count == 1)
    }

    @Test func v11ShapeMetadata() throws {
        let node = try parse(#"A@{ shape: cyl, label: "Store" }"#).nodes[0]
        #expect(node.shape == .cylinder && node.label == "Store")
        #expect(throws: MermaidError.self) { try parse("A@{ shape: blob }") }
    }

    @Test func linkForms() throws {
        let d = try parse("""
        A --> B
        A --- C
        A -.-> D
        A ==> E
        A ~~~ F
        A --o G
        A --x H
        A <--> I
        A ---> J
        A -- text --> K
        A -. dotted .-> L
        A == thick ==> M
        A -->|pipe| N
        A---O
        A-->P
        """)
        let links = d.links
        #expect(links.map(\.stroke) == [.normal, .normal, .dotted, .thick, .invisible, .normal, .normal, .normal,
                                        .normal, .normal, .dotted, .thick, .normal, .normal, .normal])
        #expect(links[1].endMarker == .none && links[5].endMarker == .circle && links[6].endMarker == .cross)
        #expect(links[7].startMarker == .arrow && links[7].endMarker == .arrow)
        #expect(links[8].length == 2)
        #expect(links[9].label == "text" && links[10].label == "dotted" && links[11].label == "thick")
        #expect(links[12].label == "pipe")
        #expect(links[13].to == "O" && links[14].to == "P")
    }

    @Test func chainsAndGroupsExpandToEveryPair() throws {
        let d = try parse("A & B --> C & D --> E")
        #expect(d.links.map { "\($0.from)\($0.to)" } == ["AC", "AD", "BC", "BD", "CE", "DE"])
    }

    @Test func subgraphMembershipAndNesting() throws {
        let d = try parse("""
        X --> A
        subgraph outer [Outer title]
          direction LR
          A
          subgraph inner
            B --> C
          end
        end
        """)
        let outer = try #require(d.subgraphs.first { $0.id == "outer" })
        let inner = try #require(d.subgraphs.first { $0.id == "inner" })
        #expect(outer.title == "Outer title" && outer.direction == .leftToRight)
        #expect(inner.parent == "outer")
        #expect(inner.nodes == ["B", "C"])
        #expect(outer.nodes == ["A"])
    }

    @Test func linksToSubgraphsAreNotNodes() throws {
        let d = try parse("subgraph S\n  A\nend\nB --> S")
        #expect(!d.nodes.contains { $0.id == "S" })
        #expect(d.links[0].to == "S")
    }

    @Test func stylingStatements() throws {
        let d = try parse("""
        A:::hot --> B
        classDef hot fill:#f00,stroke:#333
        classDef cold,frozen fill:#00f
        class B cold
        style A stroke-width:4px
        linkStyle 0 stroke:#0f0 ,stroke-width:2px
        linkStyle default interpolate linear stroke:#999
        click A "https://example.com" "Go"
        """)
        #expect(d.classDefinitions["hot"]?.fill == Color(hex: 0xFF0000))
        #expect(d.classDefinitions["frozen"]?.fill == Color(hex: 0x0000FF))
        #expect(d.node("A")?.classes == ["hot"] && d.node("B")?.classes == ["cold"])
        #expect(d.node("A")?.style.strokeWidth == 4)
        #expect(d.linkStyles[0]?.stroke == Color(hex: 0x00FF00))
        #expect(d.defaultLinkCurve == .linear && d.defaultLinkStyle.stroke == Color(hex: 0x999999))
        #expect(d.node("A")?.link == "https://example.com" && d.node("A")?.tooltip == "Go")
    }

    @Test func capitalizedEndIsANode() throws {
        #expect(try parse("Start --> End").nodes.map(\.id) == ["Start", "End"])
    }

    @Test func errorsAreLocated() {
        do {
            _ = try parse("A --> B\nC[unclosed --> D")
            Issue.record("expected an error")
        } catch let error as MermaidError {
            #expect(error.location?.line == 3)
        } catch {
            Issue.record("unexpected \(error)")
        }
        #expect(throws: MermaidError.self) { try parse("subgraph S\nA") }
        #expect(throws: MermaidError.self) { try parse("end") }
    }
}
