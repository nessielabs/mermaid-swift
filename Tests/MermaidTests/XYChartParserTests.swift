import Testing
@testable import Mermaid

@Suite("XY chart parsing")
struct XYChartParserTests {
    func parse(_ source: String) throws -> XYChartDiagram {
        let prepared = try Preprocessor.prepare(source)
        return try XYChartParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func fullExample() throws {
        let d = try parse("""
        xychart-beta
            title "Sales Revenue"
            x-axis [jan, feb, mar, "apr 24"]
            y-axis "Revenue (in $)" 4000 --> 11000
            bar [5000, 6000, 7500, 8200]
            line [5000, 6000, 7500, 8200]
        """)
        #expect(d.orientation == nil)
        #expect(d.title == "Sales Revenue")
        #expect(d.xAxis == .categories(["jan", "feb", "mar", "apr 24"]))
        #expect(d.xAxisTitle == nil)
        #expect(d.yAxisTitle == "Revenue (in $)" && d.yAxisRange == .init(4000, 11000))
        #expect(d.series.map(\.kind) == [.bar, .line])
        #expect(d.series[0].values == [5000, 6000, 7500, 8200])
    }

    @Test func orientationAndHeaderKeywords() throws {
        #expect(try parse("xychart horizontal\nbar [1]").orientation == .horizontal)
        #expect(try parse("xychart-beta VERTICAL\nbar [1]").orientation == .vertical)
        let error = try #require(throws: MermaidError.self) { try parse("xychart sideways\nbar [1]") }
        #expect(error.location == SourceLocation(line: 1, column: 9))
    }

    @Test func numericAxesAndTitles() throws {
        let d = try parse("""
        xychart
            x-axis "Year" 2018 --> 2024
            y-axis Score
            line [+1.3, .6, 2.4, -.34]
        """)
        #expect(d.xAxisTitle == "Year" && d.xAxis == .range(.init(2018, 2024)))
        #expect(d.yAxisTitle == "Score" && d.yAxisRange == nil)
        #expect(d.series[0].values == [1.3, 0.6, 2.4, -0.34])
        let bare = try parse("xychart\n x-axis 0 --> 1; y-axis 10 --> 0\n bar [1]")
        #expect(bare.xAxisTitle == nil && bare.xAxis == .range(.init(0, 1)))
        #expect(bare.yAxisRange == .init(10, 0))
    }

    @Test func seriesTitlesAndPointLabels() throws {
        let d = try parse("""
        xychart
            line "p95" [112.2, 75.3]
            bar Sales [1, 2]
            line [540 "PaLM", 65, 34 "Llama 2, 34B"]
        """)
        #expect(d.series.map(\.title) == ["p95", "Sales", nil])
        #expect(d.series[2].values == [540, 65, 34])
        #expect(d.series[2].pointLabels == ["PaLM", nil, "Llama 2, 34B"])
        #expect(d.series[0].pointLabels.isEmpty)
    }

    @Test func markdownTitlesKeepBackticks() throws {
        let d = try parse("xychart\n title \"`**Bold** title`\"\n bar [1]")
        #expect(d.title == "`**Bold** title`")
    }

    @Test func errorsAreLocated() throws {
        let cases: [(String, Int, Int)] = [
            ("xychart\n  bar [1, x, 3]", 2, 11),
            ("xychart\n  bar [1, 2", 2, 12),
            ("xychart\n  bar []", 2, 7),
            ("xychart\n  line", 2, 7),
            ("xychart\n  y-axis [a, b]\n  bar [1]", 2, 10),
            ("xychart\n  x-axis 1 --> x\n  bar [1]", 2, 10),
            ("xychart\n  bar [1] extra", 2, 10),
            ("xychart\n  pie [1]", 2, 3),
        ]
        for (source, line, column) in cases {
            let error = try #require(throws: MermaidError.self) { try parse(source) }
            #expect(error.location == SourceLocation(line: line, column: column), "\(source): \(error)")
        }
        let empty = try #require(throws: MermaidError.self) { try parse("xychart\n  title Nothing") }
        #expect(empty.kind == .semantic)
    }
}
