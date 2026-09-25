import Testing
@testable import Mermaid

@Suite("Label parsing")
struct LabelParserTests {
    typealias Span = RichText.Span

    @Test func breaksAndInlineTags() {
        let text = LabelParser.parse("Build <b>server</b><br/>in <i>staging</i> cluster")
        #expect(text.lines == [
            [Span("Build "), Span("server", bold: true)],
            [Span("in "), Span("staging", italic: true), Span(" cluster")],
        ])
    }

    @Test func entitiesDecode() {
        #expect(LabelParser.parse("A #quot;quoted#quot; #35;1 &amp; #x2665;").plainText == "A \"quoted\" #1 & ♥")
        #expect(LabelParser.parse("a &lt;b&gt; c").plainText == "a <b> c")
    }

    @Test func bareAngleBracketStaysLiteral() {
        #expect(LabelParser.parse("x < y and y > z").plainText == "x < y and y > z")
    }

    @Test func unknownTagsAndIconsAreDropped() {
        #expect(LabelParser.parse("<span class='x'>fa:fa-car Drive</span>").plainText == "Drive")
    }

    @Test func markdownStringsWrapAndStyle() {
        let text = LabelParser.parse("`The **cat** in\n    the *hat*`")
        #expect(text.wraps)
        #expect(text.lines == [
            [Span("The "), Span("cat", bold: true), Span(" in")],
            [Span("the "), Span("hat", italic: true)],
        ])
    }

    @Test func loneMarkdownMarkersStayLiteral() {
        #expect(LabelParser.parse("`2 * 3 = 6`").plainText == "2 * 3 = 6")
        #expect(LabelParser.parse("`snake_case`").plainText == "snake_case")
    }

    @Test func plainLabelsDoNotWrap() {
        #expect(!LabelParser.parse("hello").wraps)
    }
}
