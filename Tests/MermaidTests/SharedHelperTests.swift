import Testing
@testable import Mermaid

@Suite("Shared parsing and text helpers")
struct SharedHelperTests {
    @Test func readsQuotedStringsWithEscapes() throws {
        var s = Scanner(#""a \"b\" c" rest"#)
        #expect(try s.readQuoted() == #"a "b" c"#)
        #expect(s.peek() == " ")
        var single = Scanner("'x'")
        #expect(try single.readQuoted() == "x")
        var none = Scanner("x")
        #expect(try none.readQuoted() == nil)
        var open = Scanner("\"never closed")
        #expect(throws: MermaidError.self) { try open.readQuoted() }
    }

    @Test func stripsTrailingCommentsOutsideQuotes() {
        let line = SourceLine(number: 1, text: #"0-7: "50%% off" %% note"#, indent: 0)
        #expect(line.textWithoutComment == #"0-7: "50%% off""#)
        #expect(SourceLine(number: 1, text: "plain", indent: 0).textWithoutComment == "plain")
    }

    @Test func fitsTextByWrappingThenShrinking() throws {
        let fitting = TextFitting(measurer: ApproximateTextMeasurer(), font: Font(size: 20), minimumSize: 6)
        let text = RichText(plain: "alpha beta gamma delta")
        let block = try #require(fitting.fit(text, in: Size(80, 60)))
        #expect(block.width <= 80 && block.height <= 60)
        #expect(block.lines.count > 1)
        #expect(fitting.fit(text, in: Size(4, 4)) == nil)
    }

    @Test func truncatesSingleLinesWithAnEllipsis() throws {
        let fitting = TextFitting(measurer: ApproximateTextMeasurer(), font: Font(size: 12), minimumSize: 12)
        let block = try #require(fitting.fitSingleLine("a rather long section name", width: 60))
        let text = block.lines[0].runs.map(\.text).joined()
        #expect(text.hasSuffix("…"))
        #expect(block.width <= 60)
    }
}
