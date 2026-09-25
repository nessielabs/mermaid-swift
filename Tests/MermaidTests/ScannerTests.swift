import Testing
@testable import Mermaid

@Suite("Scanner")
struct ScannerTests {
    @Test func tracksLinesAndColumns() {
        var scanner = Scanner("ab\ncd")
        scanner.advance(by: 3)
        #expect(scanner.location == SourceLocation(line: 2, column: 1))
        scanner.advance()
        #expect(scanner.location == SourceLocation(line: 2, column: 2))
    }

    @Test func keywordsRespectWordBoundaries() {
        var scanner = Scanner("endpoint")
        let matchedPrefix = scanner.consumeKeyword("end")
        #expect(!matchedPrefix)
        scanner = Scanner("end-->x")
        let matchedKeyword = scanner.consumeKeyword("end")
        #expect(matchedKeyword)
    }

    @Test func readUntilBacktracksWhenMissing() {
        var scanner = Scanner("abc")
        let missing = scanner.read(until: "]")
        #expect(missing == nil)
        #expect(scanner.peek() == "a")
        let found = scanner.read(until: "c")
        #expect(found == "ab")
    }

    @Test func columnsCountGraphemesNotScalars() {
        var scanner = Scanner("👩‍💻x")
        scanner.advance()
        #expect(scanner.peek() == "x")
        #expect(scanner.location.column == 2)
    }
}
