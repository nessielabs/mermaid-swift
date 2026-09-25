import Testing
@testable import Mermaid

@Suite("Entity relationship parsing")
struct EntityRelationshipParserTests {
    typealias ER = EntityRelationshipDiagram

    func parse(_ body: String, header: String = "erDiagram") throws -> ER {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try EntityRelationshipParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    func location(of body: String) -> String? {
        do {
            _ = try parse(body)
            return nil
        } catch let error as MermaidError {
            return error.location?.description
        } catch {
            return nil
        }
    }

    @Test func symbolCardinalities() throws {
        let d = try parse("""
        A |o--o| B : a
        A ||--|| B : b
        A }o--o{ B : c
        A }|--|{ B : d
        A u--|| B : e
        """)
        let pairs = d.relationships.map { [$0.fromCardinality, $0.toCardinality] }
        #expect(pairs == [[.zeroOrOne, .zeroOrOne], [.exactlyOne, .exactlyOne], [.zeroOrMore, .zeroOrMore],
                          [.oneOrMore, .oneOrMore], [.mdParent, .exactlyOne]])
        #expect(d.entities.map(\.name) == ["A", "B"])
    }

    @Test func wordCardinalitiesAndLines() throws {
        let d = try parse("""
        CAR 1 to zero or more NAMED-DRIVER : allows
        PERSON many(0) optionally to 1+ CAR : drives
        A one or zero to one or more B : x
        A zero or one .. one or many B : x
        A zero or many -. many(1) B : x
        A only one .- 0+ B : x
        A one -- many B : x
        """)
        let r = d.relationships
        #expect(r.map(\.fromCardinality) == [.exactlyOne, .zeroOrMore, .zeroOrOne, .zeroOrOne, .zeroOrMore, .exactlyOne, .exactlyOne])
        #expect(r.map(\.toCardinality) == [.zeroOrMore, .oneOrMore, .oneOrMore, .oneOrMore, .oneOrMore, .zeroOrMore, .zeroOrMore])
        #expect(r.map(\.identifying) == [true, false, true, false, false, false, true])
        #expect(r[0].to == "NAMED-DRIVER" && r[0].label == "allows")
    }

    @Test func labelsQuotedUnquotedAndMissing() throws {
        let d = try parse("""
        CUSTOMER ||--o{ ORDER : places
        ORDER ||--|{ LINE-ITEM : "contains many"
        A ||--|| B : ""
        CUSTOMER}|..|{DELIVERY-ADDRESS : uses
        X ||--|| Y
        """)
        #expect(d.relationships.map(\.label) == ["places", "contains many", "", "uses", ""])
        #expect(d.relationships[3].to == "DELIVERY-ADDRESS" && !d.relationships[3].identifying)
    }

    @Test func attributeBlocks() throws {
        let d = try parse("""
        CUSTOMER {
            string name "the customer's name"
            string custNumber PK, FK "comment with { brace }"
            decimal(10,2) balance
            varchar[] tags UK
            type~T~ generic
            `long type` `long name`
            *string starred PK,FK,UK
        }
        EMPTY { }
        ONE_LINE { int id PK }
        """)
        let attributes = try #require(d.entity("CUSTOMER")?.attributes)
        #expect(attributes.map(\.type) == ["string", "string", "decimal(10,2)", "varchar[]", "type<T>", "long type", "*string"])
        #expect(attributes[0].comment == "the customer's name")
        #expect(attributes[1].keys == ["PK", "FK"] && attributes[1].comment == "comment with { brace }")
        #expect(attributes[3].keys == ["UK"])
        #expect(attributes[5].name == "long name")
        #expect(attributes[6].keys == ["PK", "FK", "UK"])
        #expect(d.entity("EMPTY")?.attributes.isEmpty == true)
        #expect(d.entity("ONE_LINE")?.attributes == [ER.Attribute(type: "int", name: "id", keys: ["PK"])])
    }

    @Test func strayWordsBecomeKeysAndPairsSplit() throws {
        let d = try parse("""
        CONNECTIONS {
            string region SK
            string sessionKey string
            string a string b
        }
        """)
        let attributes = try #require(d.entity("CONNECTIONS")?.attributes)
        #expect(attributes.map(\.name) == ["region", "sessionKey", "a", "b"])
        #expect(attributes[0].keys == ["SK"] && attributes[1].keys == ["string"])
    }

    @Test func aliasesAndUnicodeNames() throws {
        let d = try parse("""
        p[Person] {
            string name
        }
        CUSTOMER["Customer Account"]
        "Quoted Name" ||--o{ Café-Ünicode : has
        顧客 ||--|| order.line : x
        p ||--o{ CUSTOMER : knows
        """)
        #expect(d.entity("p")?.alias == "Person" && d.entity("p")?.label == "Person")
        #expect(d.entity("CUSTOMER")?.label == "Customer Account")
        #expect(d.entities.map(\.name).contains("Quoted Name"))
        #expect(d.entities.map(\.name).contains("Café-Ünicode"))
        #expect(d.relationships[1].from == "顧客" && d.relationships[1].to == "order.line")
    }

    @Test func directionAndStyling() throws {
        let d = try parse("""
        direction LR
        A:::hot ||--o{ B:::cold,frozen : x
        C:::hot { string id }
        classDef hot fill:#f00,stroke:#333
        classDef cold,frozen fill:#00f
        class C cold
        style A stroke-width:4px,color:#fff
        """)
        #expect(d.direction == .leftToRight)
        #expect(d.entity("A")?.classes == ["hot"] && d.entity("B")?.classes == ["cold", "frozen"])
        #expect(d.entity("C")?.classes == ["hot", "cold"])
        #expect(d.classDefinitions["hot"]?.fill == Color(hex: 0xFF0000))
        #expect(d.classDefinitions["frozen"]?.fill == Color(hex: 0x0000FF))
        #expect(d.entity("A")?.style.strokeWidth == 4 && d.entity("A")?.style.textColor == .white)
        #expect(try parse("A", header: "erDiagram LR").direction == .leftToRight)
    }

    @Test func entityNamedLikeKeywords() throws {
        let d = try parse("""
        Direction ||--o{ Classes : x
        End ||--|| Styles : y
        """)
        #expect(d.entities.map(\.name) == ["Direction", "Classes", "End", "Styles"])
    }

    @Test func subgraphs() throws {
        let d = try parse("""
        subgraph Sales [Sales Domain]
            direction LR
            CUSTOMER ||--o{ ORDER : places
            subgraph Billing
                INVOICE
            end
        end
        ORDER ||--|| INVOICE : billed
        PRODUCT }o--|| Sales : sold
        """)
        let sales = try #require(d.subgraphs.first { $0.id == "Sales" })
        let billing = try #require(d.subgraphs.first { $0.id == "Billing" })
        #expect(sales.title == "Sales Domain" && sales.direction == .leftToRight)
        #expect(sales.entities == ["CUSTOMER", "ORDER"] && billing.entities == ["INVOICE"])
        #expect(billing.parent == "Sales")
        #expect(!d.entities.contains { $0.name == "Sales" })
        #expect(d.relationships.last?.to == "Sales")
    }

    @Test func errorsAreLocated() {
        #expect(location(of: "A ||--o{ B\nC ||-- D") == "3:8")
        #expect(location(of: "A ||xx B")?.hasPrefix("2:") == true)
        #expect(location(of: "A {\n  string\n}") == "3:3")
        #expect(location(of: "A {\n  string name") == "2:3")
        #expect(location(of: "A ||--o{ \"B") == "2:10")
        #expect(location(of: "A ||--o{ B : x\nA junk") == "3:3")
        #expect(location(of: "subgraph S\nA") == "2:1")
        #expect(location(of: "A {\n string name \"open\n}")?.hasPrefix("3:") == true)
    }
}
