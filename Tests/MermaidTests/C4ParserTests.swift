import Testing
@testable import Mermaid

@Suite("C4 parsing")
struct C4ParserTests {
    func parse(_ body: String, header: String = "C4Context") throws -> C4Diagram {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try C4Parser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    func parseError(_ body: String) -> MermaidError? {
        do { _ = try parse(body); return nil } catch let error as MermaidError { return error } catch { return nil }
    }

    @Test func headersSelectTheKind() throws {
        #expect(try parse("", header: "C4Context").kind == .context)
        #expect(try parse("", header: "C4Container").kind == .container)
        #expect(try parse("", header: "C4Component").kind == .component)
        #expect(try parse("", header: "C4Dynamic").kind == .dynamic)
        #expect(try parse("", header: "C4Deployment").kind == .deployment)
    }

    @Test func everyElementMacro() throws {
        let names = ["Person", "Person_Ext", "System", "SystemDb", "SystemQueue", "System_Ext", "SystemDb_Ext",
                     "SystemQueue_Ext", "Container", "ContainerDb", "ContainerQueue", "Container_Ext",
                     "ContainerDb_Ext", "ContainerQueue_Ext", "Component", "ComponentDb", "ComponentQueue",
                     "Component_Ext", "ComponentDb_Ext", "ComponentQueue_Ext"]
        let body = names.enumerated().map { "\($0.element)(e\($0.offset), \"L\")" }.joined(separator: "\n")
        let types = try parse(body).elements.map(\.typeName)
        #expect(types == ["person", "external_person", "system", "system_db", "system_queue", "external_system",
                          "external_system_db", "external_system_queue", "container", "container_db",
                          "container_queue", "external_container", "external_container_db",
                          "external_container_queue", "component", "component_db", "component_queue",
                          "external_component", "external_component_db", "external_component_queue"])
    }

    @Test func positionalArgumentsFollowTheSignature() throws {
        let d = try parse("""
        Person(p, "Customer", "A customer", "sprite", "tag1+tag2", "https://x")
        Container(c, "API", "Go", "Serves requests")
        """)
        let person = try #require(d.element("p"))
        #expect(person.label == "Customer" && person.description == "A customer" && person.technology.isEmpty)
        #expect(person.sprite == "sprite" && person.tags == ["tag1", "tag2"] && person.link == "https://x")
        let container = try #require(d.element("c"))
        #expect(container.technology == "Go" && container.description == "Serves requests")
    }

    @Test func namedArgumentsSetTheirOwnField() throws {
        let d = try parse("""
        Container(c, "API", $descr="Serves requests", $techn="Go")
        Person(customer, Customer, "A customer", $tags="v1.0")
        Container(x, "X", , "Only description")
        """)
        #expect(d.element("c")?.technology == "Go")
        #expect(d.element("c")?.description == "Serves requests")
        #expect(d.element("customer")?.label == "Customer")
        #expect(d.element("customer")?.tags == ["v1.0"])
        #expect(d.element("x")?.technology == "" && d.element("x")?.description == "Only description")
    }

    @Test func boundariesNestWithBlocks() throws {
        let d = try parse("""
        Enterprise_Boundary(b0, "Bank") {
          Person(a, "A")
          System_Boundary(b1, "Inner")
          {
            System(s, "S")
          }
          Boundary(b2, "Custom", "team") { System(t, "T") }
        }
        Container_Boundary(c1, "Web") {
        }
        """)
        #expect(d.boundaries.map(\.alias) == ["b0", "b1", "b2", "c1"])
        #expect(d.boundaries.map(\.type) == ["ENTERPRISE", "SYSTEM", "team", "CONTAINER"])
        #expect(d.boundaries.map(\.parent) == [nil, "b0", "b0", nil])
        #expect(d.element("a")?.boundary == "b0" && d.element("s")?.boundary == "b1" && d.element("t")?.boundary == "b2")
    }

    @Test func deploymentNodes() throws {
        let d = try parse("""
        Deployment_Node(dn, "Server", "Ubuntu", "A box") {
          Node_L(l, "Left") { Container(c, "C") }
          Node_R(r, "Right") {
          }
          Node(n, "Plain", $descr="d") {
          }
        }
        """, header: "C4Deployment")
        #expect(d.boundary("dn")?.type == "Ubuntu" && d.boundary("dn")?.description == "A box")
        #expect(d.boundary("l")?.kind == .deploymentNode(.leading))
        #expect(d.boundary("r")?.kind == .deploymentNode(.trailing))
        #expect(d.boundary("n")?.kind == .deploymentNode(nil) && d.boundary("n")?.type == "node")
        #expect(d.element("c")?.boundary == "l")
    }

    @Test func relationshipKinds() throws {
        let d = try parse("""
        System(a, "A")
        System(b, "B")
        Rel(a, b, "Uses", "HTTPS")
        BiRel(a, b, "Syncs")
        Rel_U(a, b, "u")
        Rel_Up(a, b, "u")
        Rel_D(a, b, "d")
        Rel_Down(a, b, "d")
        Rel_L(a, b, "l")
        Rel_Left(a, b, "l")
        Rel_R(a, b, "r")
        Rel_Right(a, b, "r")
        Rel_Back(a, b, "back")
        RelIndex(7, a, b, "indexed", "JDBC")
        """)
        #expect(d.relationships.map(\.kind) == [.rel, .biRel, .up, .up, .down, .down, .left, .left, .right, .right,
                                                 .back, .rel])
        #expect(d.relationships[0].technology == "HTTPS")
        #expect(d.relationships[11].index == "7" && d.relationships[11].label == "indexed")
        #expect(d.relationships[11].technology == "JDBC")
        #expect(d.relationships[10].arrowAtSource && !d.relationships[10].arrowAtTarget)
        #expect(d.relationships[1].arrowAtSource && d.relationships[1].arrowAtTarget)
    }

    @Test func styleStatements() throws {
        let d = try parse("""
        Person(a, "A")
        System(b, "B")
        Rel(a, b, "Uses")
        UpdateElementStyle(a, $fontColor="red", $bgColor="grey", $borderColor="red")
        UpdateRelStyle(a, b, "blue", "green", "-40", $offsetY="60")
        UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
        """)
        let a = try #require(d.element("a"))
        #expect(a.style.font == Color(css: "red") && a.style.background == Color(css: "grey"))
        let rel = d.relationships[0]
        #expect(rel.textColor == Color(css: "blue") && rel.lineColor == Color(css: "green"))
        #expect(rel.offsetX == -40 && rel.offsetY == 60)
        #expect(d.shapesPerRow == 3 && d.boundariesPerRow == 1)
    }

    @Test func titleCommentsAndTags() throws {
        let d = try parse("""
        title System Context for Banking
        %% a comment
        AddElementTag("v1", $bgColor="#ff0000")
        AddRelTag("async", $lineStyle="DashedLine()")
        SHOW_LEGEND()
        Lay_R(a, b)
        System(a, "A", $tags="v1")
        """)
        #expect(d.title == "System Context for Banking")
        #expect(d.elementTags["v1"]?.background == Color(hex: 0xFF0000))
        #expect(d.relationshipTags["async"]?.lineStyle == "DashedLine()")
        #expect(d.elements.count == 1)
    }

    @Test func redeclarationUpdatesTheElement() throws {
        let d = try parse("""
        System(a, "First")
        System_Ext(a, "Second")
        """)
        #expect(d.elements.count == 1 && d.elements[0].label == "Second" && d.elements[0].isExternal)
    }

    @Test func errorsAreLocated() throws {
        #expect(parseError("Person(a, \"A\"\nSystem(b, \"B\")")?.location == SourceLocation(line: 2, column: 7))
        #expect(parseError("Bogus(a, \"A\")")?.location == SourceLocation(line: 2, column: 1))
        #expect(parseError("  }")?.location == SourceLocation(line: 2, column: 3))
        #expect(parseError("Boundary(b, \"B\") {\n  Person(a, \"A\")")?.location == SourceLocation(line: 2, column: 1))
        #expect(parseError("Person(, \"A\")")?.message.contains("alias") == true)
        #expect(parseError("Person(a, \"A)")?.message.contains("Unterminated") == true)
        let unknown = parseError("System(a, \"A\")\nRel(a, zz, \"Uses\")")
        #expect(unknown?.kind == .semantic && unknown?.location == SourceLocation(line: 3, column: 1))
        #expect(parseError("Person a")?.location == SourceLocation(line: 2, column: 8))
    }
}
