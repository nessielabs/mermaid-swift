import Testing
@testable import Mermaid

let ganttToday = civil(2024, 6, 15, 9, 30)

func parseGantt(_ body: String, today: CivilDateTime = ganttToday) throws -> GanttDiagram {
    let prepared = try Preprocessor.prepare("gantt\n" + body)
    return try GanttParser.parse(DiagramSource(prepared: prepared, header: prepared.header!), today: today)
}

@Suite("Gantt parsing")
struct GanttParserTests {
    @Test func statements() throws {
        let d = try parseGantt("""
            title  Adding GANTT diagram
            dateFormat YYYY-MM-DD ; trailing
            axisFormat %d/%m
            tickInterval 1week
            weekday monday
            weekend friday
            excludes weekends, 2024-01-01
            excludes Sunday
            includes 2024-01-06
            todayMarker stroke-width:5px,stroke:#0f0
            inclusiveEndDates
            topAxis
            accTitle: Accessible
            section A section
            Task : 2024-01-01, 1d
            """)
        #expect(d.title == "Adding GANTT diagram")
        #expect(d.dateFormat == "YYYY-MM-DD")
        #expect(d.axisFormat == "%d/%m")
        #expect(d.tickInterval == "1week")
        #expect(d.weekday == .monday)
        #expect(d.weekend == .friday)
        #expect(d.excludes == ["weekends", "2024-01-01", "sunday"])
        #expect(d.includes == ["2024-01-06"])
        #expect(d.todayMarker == "stroke-width:5px,stroke:#0f0")
        #expect(d.inclusiveEndDates && d.topAxis)
        #expect(d.accessibility.title == "Accessible")
        #expect(d.sections == ["A section"])
    }

    @Test func keywordsAreCaseInsensitive() throws {
        let d = try parseGantt("DATEFORMAT DD.MM.YYYY\nSection One\nT : 01.02.2024, 2d")
        #expect(d.dateFormat == "DD.MM.YYYY")
        #expect(d.sections == ["One"])
    }

    @Test func taskForms() throws {
        let d = try parseGantt("""
            section S
            Completed task   :done,    des1, 2014-01-06,2014-01-08
            Active task      :active,  des2, 2014-01-09, 3d
            Future task      :         des3, after des2, 5d
            Crit             :crit, done, 2014-01-06,24h
            Chained          :2d
            Until            :until des3
            Milestone        :milestone, m1, 2014-01-25, 0d
            Marker           :vert, v1, 2014-01-20, 1s
            """)
        let tasks = d.tasks
        #expect(tasks.map(\.id) == ["des1", "des2", "des3", "task1", "task2", "task3", "m1", "v1"])
        #expect(tasks[0].tags == [.done] && tasks[1].tags == [.active] && tasks[3].tags == [.crit, .done])
        #expect(tasks[2].start == .after(["des2"]))
        #expect(tasks[4].start == .previousTaskEnd && tasks[4].end == .dateOrDuration("2d"))
        #expect(tasks[5].end == .until(["des3"]))
        #expect(tasks[6].has(.milestone) && tasks[7].has(.vert))
        #expect(tasks.allSatisfy { $0.section == "S" })
    }

    @Test func tasksBeforeASectionHaveNoSection() throws {
        let d = try parseGantt("Solo : 2024-01-01, 1d")
        #expect(d.tasks[0].section == "" && d.sections.isEmpty)
    }

    @Test func clickStatementsAttachToTasks() throws {
        let d = try parseGantt("""
            A : a, 2024-01-01, 1d
            B : b, after a, 1d
            click a href "https://mermaid.js.org/"
            click b call printTask("x", y)
            click a,b call both()
            click missing href "x"
            """)
        #expect(d.task("a")?.link == "https://mermaid.js.org/")
        #expect(d.task("a")?.callback == "both")
        #expect(d.task("b")?.callback == "both")
    }

    @Test func trailingCommentsAreIgnored() throws {
        let d = try parseGantt("T : t1, 2024-01-01, 3d   %% three days\nU : 2d # hash comment")
        #expect(d.tasks[0].end == .dateOrDuration("3d"))
        #expect(d.tasks[1].end == .dateOrDuration("2d"))
    }

    @Test func locatedSyntaxErrors() throws {
        let cases: [(String, Int, Int)] = [
            ("not a task", 2, 1),
            ("T :", 2, 4),
            ("T : done", 2, 4),
            ("T : a, b, c, d", 2, 4),
            ("T : a, , 1d", 2, 4),
            ("weekday funday", 2, 9),
            ("weekend sunday", 2, 9),
        ]
        for (body, line, column) in cases {
            let error = try #require(throws: MermaidError.self, "\(body)") { try parseGantt(body) }
            #expect(error.location == SourceLocation(line: line, column: column), "\(body): \(error)")
        }
    }
}
