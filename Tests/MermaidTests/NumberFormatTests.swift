import Testing
@testable import Mermaid

@Suite("d3 number formats")
struct NumberFormatTests {
    func f(_ spec: String, _ value: Double) -> String? { NumberFormat(spec)?.format(value) }

    @Test func commonSpecifiers() {
        #expect(f(",", 1234567) == "1,234,567")
        #expect(f(",", 1234.5) == "1,234.5")
        #expect(f(".1f", 3.14159) == "3.1")
        #expect(f(",.2f", 1234.5) == "1,234.50")
        #expect(f(".0%", 0.123) == "12%")
        #expect(f(".1%", 0.35) == "35.0%")
        #expect(f("d", 41.6) == "42")
        #expect(f("x", 255) == "ff")
        #expect(f("#x", 255) == "0xff")
        #expect(f("08.2f", 3.5) == "00003.50")
        #expect(f("+,", 1000) == "+1,000")
        #expect(f("(,", -1000) == "(1,000)")
        #expect(f(",", -5) == "−5")
        #expect(f(".3s", 1_500_000) == "1.50M")
        #expect(f("~s", 1_500) == "1.5k")
        #expect(f(".2e", 12345) == "1.23e+4")
        #expect(f("^7", 12) == "  12   ")
        #expect(f("$,.2f", 12) == "$12.00")
        #expect(NumberFormat("nonsense") == nil)
    }

    @Test func mermaidCurrencyShorthands() {
        #expect(NumberFormat.mermaidValueFormat("$0,0")(700000) == "$700,000")
        #expect(NumberFormat.mermaidValueFormat("$,.2f")(1234.5) == "$1,234.50")
        #expect(NumberFormat.mermaidValueFormat("$.1%")(0.35) == "$35.0%")
        #expect(NumberFormat.mermaidValueFormat("")(1000) == "1,000")
        #expect(NumberFormat.mermaidValueFormat("???")(1000) == "1,000")
    }
}
