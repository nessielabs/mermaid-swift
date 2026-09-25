import Testing
@testable import Mermaid

@Suite("User journey")
struct JourneyTests {
    func parse(_ body: String) throws -> JourneyDiagram {
        let prepared = try Preprocessor.prepare("journey\n" + body)
        return try JourneyParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    let sample = """
        title My working day
        section Go to work
          Make tea: 5: Me
          Go upstairs: 3: Me
          Do work: 1: Me, Cat
        section Go home
          Go downstairs: 5: Me
          Sit down: 4.5
        """

    @Test func parsesTitleSectionsTasksAndActors() throws {
        let d = try parse(sample)
        #expect(d.title == "My working day")
        #expect(d.sections == ["Go to work", "Go home"])
        #expect(d.tasks.map(\.name) == ["Make tea", "Go upstairs", "Do work", "Go downstairs", "Sit down"])
        #expect(d.tasks.map(\.score) == [5, 3, 1, 5, 4.5])
        #expect(d.tasks[2].actors == ["Me", "Cat"] && d.tasks[4].actors.isEmpty)
        #expect(d.tasks.map(\.section) == [0, 0, 0, 1, 1])
        #expect(d.actors == ["Me", "Cat"])
    }

    @Test func commentsEndStatements() throws {
        let d = try parse("Task: 3: Me # trailing\n# whole line\nOther: 2; ignored")
        #expect(d.tasks.map(\.name) == ["Task", "Other"] && d.tasks[0].actors == ["Me"])
    }

    @Test func locatedErrors() throws {
        let missing = try #require(throws: MermaidError.self) { try parse("section S\n  Make tea") }
        #expect(missing.location == SourceLocation(line: 3, column: 3))
        let score = try #require(throws: MermaidError.self) { try parse("Make tea: high: Me") }
        #expect(score.location == SourceLocation(line: 2, column: 10))
    }
}
