import Testing
@testable import Mermaid

@Suite("Timeline")
struct TimelineTests {
    func parse(_ source: String) throws -> TimelineDiagram {
        let prepared = try Preprocessor.prepare(source)
        return try TimelineParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func periodsEventsAndContinuations() throws {
        let d = try parse("""
            timeline
                title History of Social Media Platform
                2002 : LinkedIn
                2004 : Facebook : Google
                     : Instagram
                2005 : YouTube : Meeting at 10:30
                2006
            """)
        #expect(d.title == "History of Social Media Platform")
        #expect(d.periods.map(\.text) == ["2002", "2004", "2005", "2006"])
        #expect(d.periods[1].events == ["Facebook", "Google", "Instagram"])
        // A colon without following whitespace belongs to the event text.
        #expect(d.periods[2].events == ["YouTube", "Meeting at 10:30"])
        #expect(d.periods[3].events.isEmpty)
        #expect(d.sections.isEmpty && d.periods.allSatisfy { $0.section == nil })
    }

    @Test func sectionsGroupPeriods() throws {
        let d = try parse("""
            timeline
                section 17th-20th century
                    Industry 1.0 : Machinery, Water power, Steam <br>power
                    Industry 2.0 : Electricity
                section 21st century
                    Industry 4.0 : Internet
                # a comment
            """)
        #expect(d.sections == ["17th-20th century", "21st century"])
        #expect(d.periods.map(\.section) == [0, 0, 1])
        #expect(d.periods[0].events == ["Machinery, Water power, Steam <br>power"])
    }

    @Test func directions() throws {
        #expect(try parse("timeline\n a : b").direction == .leftToRight)
        #expect(try parse("timeline LR\n a : b").direction == .leftToRight)
        #expect(try parse("timeline TD\n a : b").direction == .topToBottom)
        let error = try #require(throws: MermaidError.self) { try parse("timeline XY\n a : b") }
        #expect(error.location?.line == 1)
    }

    @Test func eventsNeedAPeriod() throws {
        let error = try #require(throws: MermaidError.self) { try parse("timeline\n  : orphan") }
        #expect(error.location == SourceLocation(line: 2, column: 3))
    }
}
