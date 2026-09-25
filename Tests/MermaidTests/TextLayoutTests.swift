import Testing
@testable import Mermaid

@Suite("Text layout")
struct TextLayoutTests {
    let measurer = ApproximateTextMeasurer()
    let font = Font(size: 10)

    @Test func stacksLinesAndMeasuresWidest() {
        let block = TextBlock(LabelParser.parse("ab<br>abcd"), font: font, measurer: measurer)
        #expect(block.lines.count == 2)
        #expect(block.width == block.lines[1].width)
        #expect(block.height == 2 * font.lineHeight)
        #expect(block.lines[1].baseline - block.lines[0].baseline == font.lineHeight)
    }

    @Test func wrapsMarkdownStringsAtWordBoundaries() {
        let block = TextBlock(LabelParser.parse("`one two three four five`"), font: font,
                              measurer: measurer, maxWidth: 40)
        #expect(block.lines.count > 1)
        #expect(block.lines.allSatisfy { $0.width <= 40 })
        let words = block.lines.map { $0.runs.map(\.text).joined() }
        #expect(words.joined(separator: " ") == "one two three four five")
    }

    @Test func plainTextIgnoresMaxWidthUnlessForced() {
        let text = LabelParser.parse("one two three four five")
        #expect(TextBlock(text, font: font, measurer: measurer, maxWidth: 40).lines.count == 1)
        #expect(TextBlock(text, font: font, measurer: measurer, maxWidth: 40, forceWrap: true).lines.count > 1)
    }

    @Test func breaksOverlongWordsByCharacter() {
        let block = TextBlock(RichText(plain: "abcdefghijklmnop"), font: font, measurer: measurer,
                              maxWidth: 30, forceWrap: true)
        #expect(block.lines.count > 1)
        #expect(block.lines.allSatisfy { $0.width <= 30 })
    }

    @Test func styledRunsUseStyledFonts() {
        let block = TextBlock(LabelParser.parse("a <b>b</b>"), font: font, measurer: measurer)
        #expect(block.lines[0].runs.map(\.font.bold) == [false, true])
        #expect(block.lines[0].runs[1].x == block.lines[0].runs[0].width)
    }

    #if canImport(CoreText)
    @Test func coreTextMeasurerResolvesDefaultFamily() {
        let measurer = CoreTextMeasurer()
        let wide = measurer.width(of: "WWWW", font: Font())
        let narrow = measurer.width(of: "iiii", font: Font())
        #expect(wide > narrow)
        #expect(measurer.metrics(for: Font()).ascent > 0)
    }
    #endif
}
