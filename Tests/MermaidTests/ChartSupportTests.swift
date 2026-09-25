import Testing
@testable import Mermaid

@Suite("Chart scales and helpers")
struct ChartSupportTests {
    @Test func ticksMatchD3() {
        #expect(ChartTicks.ticks(0, 1) == [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1])
        #expect(ChartTicks.ticks(0, 10) == Array(stride(from: 0.0, through: 10, by: 1)))
        #expect(ChartTicks.ticks(4000, 11000) == Array(stride(from: 4000.0, through: 11000, by: 500)))
        #expect(ChartTicks.ticks(-3.4, 45) == [0, 5, 10, 15, 20, 25, 30, 35, 40, 45])
        #expect(ChartTicks.ticks(0, 198.2) == [0, 20, 40, 60, 80, 100, 120, 140, 160, 180])
        #expect(ChartTicks.ticks(0, 1, count: 5) == [0, 0.2, 0.4, 0.6, 0.8, 1])
        #expect(ChartTicks.ticks(10, 0, count: 2) == [10, 5, 0])
        #expect(ChartTicks.ticks(3, 3) == [3])
        #expect(ChartTicks.ticks(0, .infinity).isEmpty)
    }

    @Test func niceExtendsToRoundValues() {
        #expect(ChartTicks.nice(0.12, 9.7) == (0, 10))
        #expect(ChartTicks.nice(-3.4, 45) == (-5, 45))
        #expect(ChartTicks.nice(5000, 11000) == (5000, 11000))
        #expect(ChartTicks.nice(1.3, 2.4) == (1.3, 2.4))
        #expect(ChartTicks.nice(0.013, 0.97) == (0, 1))
        #expect(ChartTicks.nice(7, 7) == (7, 7))
    }

    @Test func linearScaleMapsAndHandlesDegenerateDomains() {
        let scale = LinearScale(domain: (0, 10), range: (100, 0))
        #expect(scale(0) == 100 && scale(10) == 0 && scale(2.5) == 75)
        #expect(LinearScale(domain: (4, 4), range: (0, 50))(4) == 25)
    }

    @Test func numbersFormatLikeJavaScript() {
        #expect(ChartNumber.format(42) == "42")
        #expect(ChartNumber.format(42.96) == "42.96")
        #expect(ChartNumber.format(-0.34) == "-0.34")
        #expect(ChartNumber.format(0.00001) == "0.00001")
        #expect(ChartNumber.format(1.5e-5) == "0.000015")
        #expect(ChartNumber.format(1e21) == "1e+21")
        #expect(ChartNumber.format(123456789012) == "123456789012")
    }

    @Test func anchoredTextLandsOnItsAnchor() {
        let block = TextBlock(RichText(plain: "Label"), font: Font(size: 10), measurer: ApproximateTextMeasurer())
        let start = TextItem(block, at: Point(10, 20), anchor: TextAnchor(horizontal: .start, vertical: .top), color: .black)
        #expect(abs(start.frame.minX - 10) < 1e-9 && abs(start.frame.minY - 20) < 1e-9)
        let end = TextItem(block, at: Point(10, 20), anchor: .trailing, color: .black)
        #expect(abs(end.frame.maxX - 10) < 1e-9 && abs(end.frame.midY - 20) < 1e-9)
        // Rotated -90° about a start/top anchor: the text runs upward from
        // the anchor and hangs to its right.
        let rotated = TextItem(block, at: Point(0, 0), anchor: TextAnchor(horizontal: .start, vertical: .top),
                               color: .black, rotation: -90)
        let box = rotated.bounds
        #expect(abs(box.minX) < 1e-9 && abs(box.maxY) < 1e-9)
        #expect(abs(box.width - block.height) < 1e-9 && abs(box.height - block.width) < 1e-9)
    }

    @Test func themeVariablesResolveNestedNumbersAndBareHex() {
        let config = ConfigValue.object(["themeVariables": .object([
            "pieOuterStrokeWidth": .string("5px"),
            "quadrant1TextFill": .string("ff0000"),
            "xyChart": .object(["titleColor": .string("#00ff00")]),
        ])])
        let context = RenderContext(theme: Theme(config: config), measurer: ApproximateTextMeasurer(), config: config)
        #expect(context.themeNumber("pieOuterStrokeWidth", default: 2) == 5)
        #expect(context.themeNumber("missing", default: 2) == 2)
        #expect(context.themeColor("quadrant1TextFill", default: .black) == Color(hex: 0xFF0000))
        #expect(context.themeColor("xyChart", "titleColor", default: .black) == Color(hex: 0x00FF00))
        #expect(context.themeColor("xyChart", "lineColor", default: .white) == .white)
    }
}
