import Testing
@testable import Mermaid

@Suite("Timeline")
struct TimelineTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

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

    func nodes(_ layout: TimelineLayout, _ kind: TimelineLayout.Kind) -> [TimelineLayout.Node] {
        layout.nodes.filter { $0.kind == kind }
    }

    @Test func horizontalLayoutOrdersPeriodsAndStacksEvents() throws {
        let d = try parse("""
            timeline
                section A
                    p1 : e1 : a much longer event that has to wrap onto several lines of text
                    p2 : e3
                section B
                    p3 : e4
            """)
        let layout = TimelineLayout.compute(d, context: context)
        let periods = nodes(layout, .period)
        #expect(zip(periods, periods.dropFirst()).allSatisfy { $0.frame.maxX < $1.frame.minX })
        #expect(Set(periods.map(\.frame.minY)).count == 1)
        let sections = nodes(layout, .section)
        // Each section spans exactly its periods.
        #expect(sections[0].frame.minX == periods[0].frame.minX && sections[0].frame.maxX == periods[1].frame.maxX)
        #expect(sections.allSatisfy { $0.frame.maxY < periods[0].frame.minY })
        let events = nodes(layout, .event).filter { $0.period == 0 }
        #expect(events.count == 2 && events[0].frame.maxY < events[1].frame.minY)
        #expect(events[1].frame.height > events[0].frame.height)
        // The axis runs between the periods and the events.
        let axis = try #require(layout.arrows.first { !$0.dashed })
        #expect(axis.from.y > periods[0].frame.maxY && axis.from.y < events[0].frame.minY)
        #expect(axis.to.x > periods.last!.frame.maxX)
    }

    @Test func colorsFollowSectionsOrPeriods() throws {
        let sectioned = TimelineLayout.compute(try parse("timeline\n section A\n a : x\n b : y\n section B\n c : z"), context: context)
        #expect(nodes(sectioned, .period).map(\.colorIndex) == [0, 0, 1])
        let plain = TimelineLayout.compute(try parse("timeline\n a : x\n b : y\n c : z"), context: context)
        #expect(nodes(plain, .period).map(\.colorIndex) == [0, 1, 2])
        #expect(nodes(plain, .event).map(\.colorIndex) == [0, 1, 2])
        var single = context
        single.config = .object(["timeline": .object(["disableMulticolor": .bool(true)])])
        let mono = TimelineLayout.compute(try parse("timeline\n a : x\n b : y"), context: single)
        #expect(nodes(mono, .period).map(\.colorIndex) == [0, 0])
    }

    @Test func verticalLayoutPutsPeriodsLeftAndEventsRight() throws {
        let d = try parse("""
            timeline TD
                section Q1
                    Bullet 1 : sub-point 1a : sub-point 1b
                    Bullet 2 : sub-point 2a
                section Q2
                    Bullet 3 : sub-point 3a
            """)
        let layout = TimelineLayout.compute(d, context: context)
        let axis = try #require(layout.arrows.first { !$0.dashed })
        #expect(axis.from.x == axis.to.x)
        let periods = nodes(layout, .period), events = nodes(layout, .event)
        #expect(periods.allSatisfy { $0.frame.maxX < axis.from.x })
        #expect(events.allSatisfy { $0.frame.minX > axis.from.x })
        #expect(zip(periods, periods.dropFirst()).allSatisfy { $0.frame.maxY < $1.frame.minY })
        #expect(layout.arrows.filter(\.dashed).count == events.count)
        // Nodes never overlap.
        for (i, a) in layout.nodes.enumerated() {
            for b in layout.nodes[(i + 1)...] {
                #expect(!a.frame.insetBy(dx: 1, dy: 1).intersects(b.frame.insetBy(dx: 1, dy: 1)))
            }
        }
    }

    @Test func rendersThroughTheRegistry() throws {
        #expect(Mermaid.detectType("timeline\n a : b") == .timeline)
        let scene = try Mermaid.render("timeline\n title T\n 2002 : LinkedIn",
                                       options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(scene.svg.contains(">LinkedIn</text>") && scene.svg.contains(">T</text>"))
    }
}
