import Testing
@testable import Mermaid

@Suite("Requirement parsing")
struct RequirementParserTests {
    typealias R = RequirementDiagram

    func parse(_ body: String, header: String = "requirementDiagram") throws -> R {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try RequirementParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
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

    @Test func everyRequirementKindAndField() throws {
        let kinds = R.Kind.allCases
        let body = kinds.enumerated().map { i, kind in
            "\(kind.keyword) r\(i) {\n  id: \(i).1\n  text: the text, with - dashes\n  risk: HIGH\n  verifyMethod: analysis\n}"
        }.joined(separator: "\n")
        let d = try parse(body)
        #expect(d.requirements.map(\.kind) == kinds)
        let first = try #require(d.requirement("r0"))
        #expect(first.id == "0.1" && first.text == "the text, with - dashes")
        #expect(first.risk == .high && first.verifyMethod == .analysis)
    }

    @Test func caseInsensitiveKeywordsAndQuotedValues() throws {
        let d = try parse("""
        FUNCTIONALREQUIREMENT "Quoted name" {
            ID: "REQ-1"
            Text: "Quoted: text"
            RISK: medium
            verifymethod: Demonstration
        }
        Element sim {
            TYPE: "test suite"
            DocRef: reqs/sim
        }
        """)
        let requirement = try #require(d.requirement("Quoted name"))
        #expect(requirement.kind == .functionalRequirement && requirement.id == "REQ-1")
        #expect(requirement.text == "Quoted: text" && requirement.risk == .medium)
        #expect(requirement.verifyMethod == .demonstration)
        #expect(d.element("sim")?.type == "test suite" && d.element("sim")?.docRef == "reqs/sim")
    }

    @Test func everyRelationshipTypeAndDirection() throws {
        let lines = R.RelationshipType.allCases.map { "a - \($0.rawValue) -> b" }.joined(separator: "\n")
        let d = try parse(lines + "\nb <- satisfies - test entity\n\"x-y\" - traces -> a")
        #expect(d.relationships.prefix(7).map(\.type) == R.RelationshipType.allCases)
        #expect(d.relationships[7] == R.Relationship(source: "test entity", target: "b", type: .satisfies))
        #expect(d.relationships[8].source == "x-y")
    }

    @Test func directionAndStyling() throws {
        let d = try parse("""
        direction LR
        requirement a:::hot {
            id: 1
        }
        element b {
        }
        requirement c {
        }
        classDef hot,warm fill:#f00,stroke:#333
        class b,c warm
        c:::extra
        style a fill:#0f0,stroke-width:3px
        """)
        #expect(d.direction == .leftToRight)
        #expect(d.requirement("a")?.classes == ["hot"])
        #expect(d.element("b")?.classes == ["warm"] && d.requirement("c")?.classes == ["warm", "extra"])
        #expect(d.classDefinitions["warm"]?.fill == Color(hex: 0xFF0000))
        #expect(d.requirement("a")?.style.fill == Color(hex: 0x00FF00) && d.requirement("a")?.style.strokeWidth == 3)
    }

    @Test func firstDeclarationWins() throws {
        let d = try parse("requirement a {\nid: 1\n}\nrequirement a {\nid: 2\n}")
        #expect(d.requirements.count == 1 && d.requirement("a")?.id == "1")
    }

    @Test func errorsAreLocated() {
        #expect(location(of: "requirement a {\n  risk: extreme\n}") == "3:3")
        #expect(location(of: "requirement a {\n  colour: red\n}") == "3:3")
        #expect(location(of: "requirement a {\n  id: 1") == "2:1")
        #expect(location(of: "widget a {\n}") == "2:1")
        #expect(location(of: "a - likes -> b") == "2:5")
        #expect(location(of: "a - satisfies - b") == "2:15")
        #expect(location(of: "a - satisfies ->") == "2:17")
        #expect(location(of: "just words") == "2:1")
        #expect(location(of: "direction XY") == "2:1")
        #expect(location(of: "element e {\n  id: 1\n}") == "3:3")
    }
}
