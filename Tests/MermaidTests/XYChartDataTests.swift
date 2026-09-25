import Testing
@testable import Mermaid

@Suite("XY chart data")
struct XYChartDataTests {
    func data(_ body: String) throws -> XYChartData {
        let prepared = try Preprocessor.prepare("xychart\n" + body)
        return XYChartData(try XYChartParser.parse(DiagramSource(prepared: prepared, header: prepared.header!)))
    }

    @Test func categoriesTruncateLongerSeries() throws {
        let d = try data("x-axis [a, b]\nbar [1, 2, 99]")
        #expect(d.x == .categories(["a", "b"]))
        #expect(d.plots[0].points.map(\.x) == [0, 1])
        #expect(d.plots[0].points.map(\.y) == [1, 2])
        // The dropped value does not stretch the inferred range.
        #expect(d.y == (0, 2))
    }

    @Test func numericXAxesSpreadPointsEvenly() throws {
        let d = try data("x-axis 10 --> 40\nline [1, 2, 3, 4]\nline [5]")
        #expect(d.plots[0].points.map(\.x) == [10, 20, 30, 40])
        #expect(d.plots[1].points.map(\.x) == [10])
    }

    /// Every series spreads across the whole range, as mermaid.js spreads
    /// each series over the numeric axis.
    @Test func missingXAxisNumbersPointsFromOne() throws {
        let d = try data("line [+1.3, .6, 2.4, -.34]\nbar [1, 2]")
        #expect(d.x == .linear(1, 4))
        #expect(d.plots[0].points.map(\.x) == [1, 2, 3, 4])
        #expect(d.plots[1].points.map(\.x) == [1, 4])
    }

    @Test func inferredRangesAreNiceAndBarsIncludeZero() throws {
        #expect(try data("bar [5000, 11000]").y == (0, 11000))
        #expect(try data("line [5000, 11000]").y == (5000, 11000))
        #expect(try data("line [1.3, 0.6, 2.4, -0.34]").y == (-0.4, 2.4))
        #expect(try data("bar [-3, -7]").y == (-7, 0))
        #expect(try data("line [4, 4]").y == (3.6, 4.4))
        #expect(try data("bar [0, 0]").y == (0, 1))
    }

    @Test func explicitRangesAreKeptAsWritten() throws {
        #expect(try data("y-axis 4000 --> 11000\nbar [5000]").y == (4000, 11000))
        #expect(try data("y-axis 100 --> 0\nbar [5]").y == (100, 0))
    }

    @Test func palettesParseAndSkipInvalidEntries() {
        #expect(XYChartDiagram.palette("#000000, #0000FF,nope, #00FF00") == [Color(hex: 0), Color(hex: 0xFF), Color(hex: 0xFF00)])
        for name in Theme.Name.allCases {
            #expect(XYChartDiagram.palette(XYChartDiagram.defaultPalette(for: name)).count == 10)
        }
    }
}
