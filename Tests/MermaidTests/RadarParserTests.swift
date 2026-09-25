import Testing
@testable import Mermaid

@Suite("Radar parsing")
struct RadarParserTests {
    func parse(_ source: String) throws -> RadarDiagram {
        let prepared = try Preprocessor.prepare(source)
        return try RadarParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func axesCurvesAndOptions() throws {
        let d = try parse("""
        radar-beta
          title Grades
          axis m["Math"], s["Science"], e['English']
          axis h
          curve a["Alice"]{85, 90, 80, 70}, b{70, 75.5, 85, 80}
          max 100
          min 10, ticks 4, graticule polygon, showLegend false
        """)
        #expect(d.title == "Grades")
        #expect(d.axes.map(\.id) == ["m", "s", "e", "h"])
        #expect(d.axes.map(\.label) == ["Math", "Science", "English", "h"])
        #expect(d.curves.map(\.label) == ["Alice", "b"])
        #expect(d.curves[1].values == [70, 75.5, 85, 80])
        #expect(d.max == 100 && d.min == 10 && d.ticks == 4)
        #expect(d.graticule == .polygon && !d.showLegend)
    }

    @Test func defaults() throws {
        let d = try parse("radar\n axis a, b, c\n curve x{1, 2, 3}")
        #expect(d.showLegend && d.ticks == 5 && d.max == nil && d.min == 0 && d.graticule == .circle)
        #expect(try parse("radar-beta\n title \"`**Bold**`\"").title == "`**Bold**`")
        #expect(d.resolvedMax == 3)
    }

    @Test func namedEntriesFollowAxisOrderAndMaySpanLines() throws {
        let d = try parse("""
        radar-beta:
          curve c{
            axis3: 30,
            axis1 20, axis2: 10
          }
          axis axis1, axis2, axis3
        """)
        #expect(d.curves[0].values == [20, 10, 30])
    }

    @Test func ticksAreCapped() throws {
        #expect(try parse("radar-beta\n ticks 100").ticks == RadarDiagram.maximumTicks)
    }

    @Test func commentsAndHeaderStatements() throws {
        let d = try parse("radar-beta : title Inline\n axis a %% comment\n curve c{1} %% another")
        #expect(d.title == "Inline" && d.axes.count == 1 && d.curves.count == 1)
        let error = try #require(throws: MermaidError.self) { try parse("radar-beta spokes 3") }
        #expect(error.location == SourceLocation(line: 1, column: 12))
        let colon = try #require(throws: MermaidError.self) { try parse("radar-beta: spokes 3") }
        #expect(colon.location == SourceLocation(line: 1, column: 13))
    }

    @Test func referenceErrorsAreLocated() throws {
        let unknown = try #require(throws: MermaidError.self) { try parse("radar-beta\n axis a, b\n curve c{ a: 1, z: 2 }") }
        #expect(unknown.kind == .semantic && unknown.location == SourceLocation(line: 3, column: 17))
        let missing = try #require(throws: MermaidError.self) { try parse("radar-beta\n axis a, b[\"Bee\"]\n curve c{ a: 1 }") }
        #expect(missing.message == "Missing entry for axis Bee" && missing.location == SourceLocation(line: 3, column: 8))
    }

    @Test func syntaxErrorsAreLocated() throws {
        let cases: [(String, Int, Int)] = [
            ("radar-beta\n axis a[Label]", 2, 9),
            ("radar-beta\n curve c 1, 2", 2, 10),
            ("radar-beta\n curve c{1, x}", 2, 13),
            ("radar-beta\n curve c{1, a: 2}", 2, 13),
            ("radar-beta\n graticule hexagon", 2, 12),
            ("radar-beta\n showLegend maybe", 2, 13),
            ("radar-beta\n spokes 5", 2, 2),
            ("radar-beta\n axis a b", 2, 9),
        ]
        for (source, line, column) in cases {
            let error = try #require(throws: MermaidError.self) { try parse(source) }
            #expect(error.location == SourceLocation(line: line, column: column), "\(source): \(error)")
        }
    }
}
