import Testing
@testable import Mermaid

@Suite("Gantt layout")
struct GanttLayoutTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func layout(_ body: String, config: ConfigValue = .object([:]),
                today: CivilDateTime = ganttToday) throws -> GanttLayout {
        let diagram = try parseGantt(body, today: today)
        let tasks = try diagram.schedule(today: today)
        return GanttLayout.compute(diagram: diagram, tasks: tasks, settings: GanttSettings(config),
                                   context: context, today: today)
    }

    let sample = """
        dateFormat YYYY-MM-DD
        section Build
        Design     :done, d1, 2024-01-01, 5d
        Implement  :active, i1, after d1, 10d
        section Release
        Test       :crit, t1, after i1, 3d
        Ship       :milestone, s1, after t1, 0d
        Freeze     :vert, v1, 2024-01-10, 0d
        """

    @Test func rowsFollowDeclarationOrderWithoutOverlap() throws {
        let l = try layout(sample)
        #expect(l.bars.map(\.task.task.id) == ["d1", "i1", "t1", "s1"])
        #expect(l.bars.map(\.row) == [0, 1, 2, 3])
        for (a, b) in zip(l.bars, l.bars.dropFirst()) {
            #expect(a.frame.maxY < b.frame.minY)
        }
        // Vertical markers take no row.
        #expect(l.rows.count == 4 && l.markers.map(\.task.task.id) == ["v1"])
        #expect(l.height == 2 * 50 + 4 * 24)
    }

    @Test func barsSpanTheirDatesOnOneScale() throws {
        let l = try layout(sample)
        let design = l.bars[0], implement = l.bars[1]
        #expect(design.frame.minX == l.leftPadding)
        #expect(design.frame.maxX == implement.frame.minX)
        #expect(abs(implement.frame.width - 2 * design.frame.width) <= 1)
        // The last end maps to the right edge of the chart area.
        #expect(l.x(CivilDateTime(milliseconds: l.domain.upperBound)) == l.width - 75)
    }

    @Test func milestonesAreSquaresCenteredOnTheirDate() throws {
        let l = try layout("M : milestone, m, 2024-01-02, 2d\nT : t, 2024-01-01, 6d")
        let m = l.bars[0]
        #expect(m.frame.width == 20 && m.frame.height == 20)
        #expect(abs(m.frame.midX - l.x(civil(2024, 1, 3))) <= 1)
    }

    @Test func labelsGoInsideWhenTheyFitAndBesideOtherwise() throws {
        let l = try layout("""
            A very long task name that cannot fit : a, 2024-01-01, 1d
            Wide : b, 2024-01-01, 30d
            Ends late with long text : c, 2024-01-30, 1d
            """)
        #expect(!l.bars[0].labelInside && l.bars[0].labelAlignment == .leading)
        #expect(l.bars[0].labelFrame.minX == l.bars[0].frame.maxX + 5)
        #expect(l.bars[1].labelInside && l.bars[1].labelAlignment == .center)
        #expect(l.bars[1].frame.contains(l.bars[1].labelFrame.center))
        #expect(l.bars[2].labelAlignment == .trailing && l.bars[2].labelFrame.maxX == l.bars[2].frame.minX - 5)
    }

    @Test func compactModePacksNonOverlappingTasks() throws {
        let config = ConfigValue.object(["displayMode": .string("compact")])
        let l = try layout("""
            section S
            A : a1, 2014-01-01, 30d
            B : a2, 2014-01-20, 25d
            C : a3, 2014-02-10, 20d
            section T
            D : d1, 2014-01-01, 3d
            """, config: config)
        #expect(l.bars.map(\.row) == [0, 1, 0, 2])
        #expect(l.height == 2 * 50 + 3 * 24)
        #expect(l.sections.map(\.name) == ["S", "T"])
    }

    @Test func sectionTitlesCenterOnTheirRowsAndFitTheMargin() throws {
        let l = try layout(sample)
        #expect(l.sections.map(\.centerY) == [74.0, 122.0])
        let longName = try layout("section A rather long section title\nT : 2024-01-01, 1d")
        let titleWidth = context.label("A rather long section title", size: 11).width
        #expect(longName.leftPadding >= 10 + titleWidth + 10)
        let configured = try layout(sample, config: .object(["leftPadding": .number(40)]))
        #expect(configured.leftPadding == 40)
    }

    @Test func ticksUseTheIntervalAndFormat() throws {
        let l = try layout("""
            axisFormat %d %b
            tickInterval 1week
            weekday monday
            T : 2024-01-01, 20d
            """)
        #expect(l.ticks.map(\.label) == ["01 Jan", "08 Jan", "15 Jan"])
        let auto = try layout("T : 2024-01-01, 10d")
        #expect(auto.ticks.count == 11 && auto.ticks.first?.label == "2024-01-01")
        let spaced = try layout("axisFormat %b %e\nT : 2024-01-01, 10d")
        #expect(spaced.ticks.first?.label == "Jan 1")
    }

    @Test func excludedDaysBecomeBands() throws {
        // 2024-01-06 and 07 are a weekend.
        let l = try layout("excludes weekends\nT : 2024-01-01, 2024-01-10")
        #expect(l.excludedRanges.count == 1)
        let band = try #require(l.excludedRanges.first)
        #expect(band.minX == l.x(civil(2024, 1, 6)))
        #expect(abs(band.maxX - l.x(civil(2024, 1, 8))) <= 1)
    }

    @Test func todayMarkerOnlyWithinRange() throws {
        let inside = try layout("T : 2024-06-01, 30d")
        #expect(inside.todayX == inside.x(ganttToday))
        #expect(try layout("T : 2024-01-01, 3d").todayX == nil)
        #expect(try layout("todayMarker off\nT : 2024-06-01, 30d").todayX == nil)
    }

    @Test func sceneRendersEveryTaskAndStylesToday() throws {
        var diagram = try parseGantt("""
            title Plan
            todayMarker stroke:#00ff00,stroke-width:5px
            section S
            A : a, 2024-06-01, 30d
            click a href "https://example.com"
            """)
        diagram.today = ganttToday
        let scene = try diagram.scene(in: context)
        let groups = scene.items.compactMap { item -> GroupItem? in
            if case .group(let group) = item { return group }
            return nil
        }
        #expect(groups.contains { $0.id == "a" && $0.role == "task" })
        let today = try #require(groups.first { $0.role == "today" })
        guard case .shape(let line) = today.items.first else { Issue.record("no today line"); return }
        #expect(line.stroke?.color == Color(hex: 0x00FF00) && line.stroke?.width == 5)
        #expect(scene.svg.contains(">Plan</text>"))
    }

    @Test func registeredWithTheDiagramRegistry() throws {
        #expect(Mermaid.detectType("gantt\n  T : 2024-01-01, 1d") == .gantt)
        let error = try #require(throws: MermaidError.self) { try Mermaid.render("gantt\n  T : nope, 1d") }
        #expect(error.location?.line == 2)
    }
}
