import Testing
@testable import Mermaid

@Suite("Styles and colors")
struct StyleTests {
    @Test func parsesHexForms() {
        #expect(Color(css: "#f00") == Color(hex: 0xFF0000))
        #expect(Color(css: "#FF000080")?.alpha ?? 0 > 0.49)
        #expect(Color(css: "#abcd")?.hexString == "#aabbccdd")
        #expect(Color(css: "#12345") == nil)
    }

    @Test func parsesFunctionalAndNamedColors() {
        #expect(Color(css: "rgb(255, 0, 0)") == Color(hex: 0xFF0000))
        #expect(Color(css: "rgba(0 0 255 / 50%)") == Color(hex: 0x0000FF, alpha: 0.5))
        #expect(Color(css: "hsl(120, 100%, 25%)")?.hexString == "#008000")
        #expect(Color(css: "RebeccaPurple") == Color(hex: 0x663399))
        #expect(Color(css: "transparent")?.isClear == true)
        #expect(Color(css: "none") == nil)
    }

    @Test func hslRoundTripsAndAdjusts() {
        let color = Color(hex: 0xECECFF)
        let back = Color(hue: color.hsl.hue, saturation: color.hsl.saturation, lightness: color.hsl.lightness)
        #expect(back.hexString == color.hexString)
        #expect(Color(hex: 0x808080).lightened(10).hsl.lightness > 0.59)
    }

    @Test func parsesDeclarationsWithParenthesizedCommas() {
        let style = ElementStyle(css: "fill:rgb(1, 2, 3),stroke:#333;stroke-width:4px, stroke-dasharray: 5 5,color:#fff !important")
        #expect(style.fill == Color(red: 1 / 255, green: 2 / 255, blue: 3 / 255))
        #expect(style.stroke == Color(hex: 0x333333))
        #expect(style.strokeWidth == 4)
        #expect(style.strokeDash == [5, 5])
        #expect(style.textColor == .white)
    }

    @Test func fontWeightAndOverlay() {
        let base = ElementStyle(css: "fill:#fff,font-weight:700")
        let top = ElementStyle(css: "fill:#000")
        let merged = base.overlaid(with: top)
        #expect(merged.fill == .black)
        #expect(merged.bold == true)
    }
}
