import Testing
@testable import Mermaid

@Suite("Quadrant chart parsing")
struct QuadrantChartParserTests {
    func parse(_ body: String) throws -> QuadrantChartDiagram {
        let prepared = try Preprocessor.prepare("quadrantChart\n" + body)
        return try QuadrantChartParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func titleAxesAndQuadrants() throws {
        let d = try parse("""
            title Reach and engagement
            x-axis Low Reach --> High Reach
            y-axis Low Engagement --> "High Engagement ❤"
            quadrant-1 We should expand
            quadrant-2 Need to promote
            quadrant-3 Re-evaluate
            QUADRANT-4 May be improved
        """)
        #expect(d.title == "Reach and engagement")
        #expect(d.xAxisLeft == "Low Reach" && d.xAxisRight == "High Reach")
        #expect(d.yAxisBottom == "Low Engagement" && d.yAxisTop == "High Engagement ❤")
        #expect(d.quadrantLabels == ["We should expand", "Need to promote", "Re-evaluate", "May be improved"])
    }

    @Test func partialAxes() throws {
        let d = try parse("x-axis Urgent -->\ny-axis Important")
        #expect(d.xAxisLeft == "Urgent ⟶ " && d.xAxisRight == nil)
        #expect(d.yAxisBottom == "Important" && d.yAxisTop == nil)
        #expect(try parse("x-axis Low ---> High").xAxisRight == "High")
    }

    @Test func markdownStringsKeepTheirBackticks() throws {
        let d = try parse(#"quadrant-1 "`**Plan**`""# + "\n" + #"title "`**Effort** vs _impact_`""#)
        #expect(d.quadrantLabels[0] == "`**Plan**`")
        #expect(d.title == "`**Effort** vs _impact_`")
    }

    @Test func pointsWithClassesAndInlineStyles() throws {
        let d = try parse("""
          Campaign A: [0.9, 0.0] radius: 12
          Campaign B:::class1: [0.8, 0.1] color: #ff3300, radius: 10
          Campaign D: [0.6, 0.3] radius: 15, stroke-color: #00ff0f, stroke-width: 5px ,color: #ff33f0
          "Point: quoted": [1, 0.25]; Other: [0.5, 0.5]
          classDef class1 color: #109060, stroke-color: #310085, stroke-width: 10px
        """)
        #expect(d.points.map(\.label) == ["Campaign A", "Campaign B", "Campaign D", "Point: quoted", "Other"])
        #expect(d.points[0].x == 0.9 && d.points[0].y == 0 && d.points[0].style.radius == 12)
        #expect(d.points[1].className == "class1")
        let b = d.resolvedStyle(of: d.points[1])
        // Inline styles win over class styles.
        #expect(b.color == Color(css: "#ff3300") && b.radius == 10)
        #expect(b.strokeColor == Color(css: "#310085") && b.strokeWidth == 10)
        let dStyle = d.points[2].style
        #expect(dStyle.strokeWidth == 5 && dStyle.color == Color(css: "#ff33f0") && dStyle.strokeColor == Color(css: "#00ff0f"))
        #expect(d.points[3].x == 1 && d.points[3].y == 0.25)
    }

    @Test func coordinatesOutsideTheUnitSquareAreLocatedErrors() throws {
        let error = try #require(throws: MermaidError.self) { try parse("  A: [1.5, 0.2]") }
        #expect(error.kind == .semantic)
        #expect(error.location == SourceLocation(line: 2, column: 7))
    }

    @Test func invalidStylesAreLocatedErrors() throws {
        for (body, message) in [("A: [0.1, 0.2] radius: big", "radius"), ("A: [0.1, 0.2] stroke-width: 4", "pixels"),
                                ("A: [0.1, 0.2] color: nope", "hex"), ("A: [0.1, 0.2] shape: star", "not supported")] {
            let error = try #require(throws: MermaidError.self) { try parse(body) }
            #expect(error.message.contains(message), "\(body)")
            #expect(error.location?.line == 2)
        }
    }

    @Test func malformedStatementsAreLocatedErrors() throws {
        let unknown = try #require(throws: MermaidError.self) { try parse("\n   what is this") }
        #expect(unknown.location == SourceLocation(line: 3, column: 4))
        let unclosed = try #require(throws: MermaidError.self) { try parse("A: [0.1, 0.2") }
        #expect(unclosed.kind == .syntax)
        let arity = try #require(throws: MermaidError.self) { try parse("A: [0.1]") }
        #expect(arity.message.contains("two coordinates"))
    }
}
