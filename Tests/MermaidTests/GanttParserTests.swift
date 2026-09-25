import Testing
@testable import Mermaid

let ganttToday = civil(2024, 6, 15, 9, 30)

func parseGantt(_ body: String, today: CivilDateTime = ganttToday) throws -> GanttDiagram {
    let prepared = try Preprocessor.prepare("gantt\n" + body)
    return try GanttParser.parse(DiagramSource(prepared: prepared, header: prepared.header!), today: today)
}

func scheduleGantt(_ body: String, today: CivilDateTime = ganttToday) throws -> [String: ScheduledGanttTask] {
    let diagram = try parseGantt(body, today: today)
    return Dictionary(try diagram.schedule(today: today).map { ($0.task.id, $0) }, uniquingKeysWith: { $1 })
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
            ("  T : 2024-13-01, 1d", 2, 6),
        ]
        for (body, line, column) in cases {
            let error = try #require(throws: MermaidError.self, "\(body)") { try parseGantt(body) }
            #expect(error.location == SourceLocation(line: line, column: column), "\(body): \(error)")
        }
    }

    @Test func firstTaskNeedsAStart() throws {
        let error = try #require(throws: MermaidError.self) { try parseGantt("T : 3d") }
        #expect(error.kind == .semantic)
    }

    @Test func cyclesAreReported() throws {
        let error = try #require(throws: MermaidError.self) {
            try parseGantt("A : a, after b, 1d\nB : b, after a, 1d")
        }
        #expect(error.message.contains("cycle"))
        #expect(error.location?.line == 2)
    }
}

@Suite("Gantt scheduling")
struct GanttScheduleTests {
    @Test func durationsAndDates() throws {
        let s = try scheduleGantt("""
            A : a, 2014-01-06, 2014-01-08
            B : b, 2014-01-09, 3d
            C : c, after b, 36h
            D : d, 2014-01-01, 2w
            E : e, 2014-01-31, 1M
            F : f, 2014-01-01, 1y
            G : g, 2014-01-01, 1.5d
            H : h, 2014-01-01, 90m
            I : i, 2014-01-01, 30s
            J : j, 2014-01-01, 250ms
            """)
        #expect(s["a"]?.end == civil(2014, 1, 8))
        #expect(s["b"]?.end == civil(2014, 1, 12))
        #expect(s["c"]?.start == civil(2014, 1, 12) && s["c"]?.end == civil(2014, 1, 13, 12))
        #expect(s["d"]?.end == civil(2014, 1, 15))
        #expect(s["e"]?.end == civil(2014, 2, 28))
        #expect(s["f"]?.end == civil(2015, 1, 1))
        #expect(s["g"]?.end == civil(2014, 1, 3))
        #expect(s["h"]?.end == civil(2014, 1, 1, 1, 30))
        #expect(s["i"]?.end == civil(2014, 1, 1, 0, 0, 30))
        #expect(s["j"]?.end == civil(2014, 1, 1, 0, 0, 0, 250))
    }

    @Test func invalidDurationsGiveZeroLength() throws {
        let s = try scheduleGantt("A : a, 2014-01-06, 3dX")
        #expect(s["a"]?.end == s["a"]?.start)
    }

    @Test func afterTakesLatestAndUntilTakesEarliest() throws {
        let s = try scheduleGantt("""
            apple  :a, 2017-07-20, 1w
            banana :crit, b, 2017-07-23, 1d
            cherry :active, c, after b a, 1d
            kiwi   :d, 2017-07-20, until b c
            """)
        #expect(s["c"]?.start == civil(2017, 7, 27))
        #expect(s["d"]?.end == civil(2017, 7, 23))
    }

    @Test func forwardReferencesResolve() throws {
        let s = try scheduleGantt("""
            Late : x, after y, 2d
            Early : y, 2024-03-01, 1d
            Next : 1d
            """)
        #expect(s["x"]?.start == civil(2024, 3, 2))
        #expect(s["task1"]?.start == civil(2024, 3, 2))
    }

    @Test func unknownReferencesFallBackToToday() throws {
        let s = try scheduleGantt("A : a, after nope, 1d\nB : b, 2024-06-01, until nope")
        #expect(s["a"]?.start == civil(2024, 6, 15))
        #expect(s["b"]?.end == civil(2024, 6, 15))
    }

    @Test func excludedDaysStretchTasks() throws {
        // 2024-01-05 is a Friday.
        let s = try scheduleGantt("""
            excludes weekends
            A : a, 2024-01-05, 3d
            B : b, 2024-01-01, 2024-01-10
            """)
        #expect(s["a"]?.end == civil(2024, 1, 10))
        // The bar stops before the trailing weekend it was pushed over.
        #expect(s["a"]?.renderEnd == civil(2024, 1, 10))
        // Explicit YYYY-MM-DD end dates are never stretched.
        #expect(s["b"]?.end == civil(2024, 1, 10))
    }

    @Test func fridayWeekendsAndSpecificDays() throws {
        let s = try scheduleGantt("""
            excludes weekends
            weekend friday
            A : a, 2024-01-04, 2d
            """)
        // Thursday + 2d spans Friday and Saturday, both excluded.
        #expect(s["a"]?.end == civil(2024, 1, 8))
        let t = try scheduleGantt("""
            excludes wednesday, 2024-01-02
            includes 2024-01-03
            A : a, 2024-01-01, 3d
            """)
        #expect(t["a"]?.end == civil(2024, 1, 5))
    }

    @Test func customFormatsExcludeByFormattedDate() throws {
        let s = try scheduleGantt("""
            dateFormat DD-MM-YYYY
            excludes 02-01-2024
            A : a, 01-01-2024, 2d
            """)
        #expect(s["a"]?.end == civil(2024, 1, 4))
    }

    @Test func inclusiveEndDatesAddADay() throws {
        let s = try scheduleGantt("inclusiveEndDates\nA : a, 2024-01-01, 2024-01-03")
        #expect(s["a"]?.end == civil(2024, 1, 4))
    }

    @Test func timeOnlyFormatsUseToday() throws {
        let s = try scheduleGantt("""
            dateFormat HH:mm
            Initial milestone : milestone, m1, 17:49, 2m
            Task A : 10m
            """)
        #expect(s["m1"]?.start == civil(2024, 6, 15, 17, 49))
        #expect(s["task1"]?.end == civil(2024, 6, 15, 18, 1))
    }

    @Test func timestampsAndISOFallback() throws {
        let s = try scheduleGantt("dateFormat X\nIssue : a, 0, 71")
        #expect(s["a"]?.start == CivilDateTime(milliseconds: 0))
        #expect(s["a"]?.end == CivilDateTime(milliseconds: 71_000))
        let t = try scheduleGantt("dateFormat DD/MM/YYYY\nA : a, 2024-02-03T10:00, 2h")
        #expect(t["a"]?.start == civil(2024, 2, 3, 10))
    }
}
