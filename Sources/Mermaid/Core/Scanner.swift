/// A character cursor over source text that tracks line and column.
///
/// Parsers use the scanner for grammars that are not strictly
/// line-oriented (flowchart statements can span `;`-separated chains and
/// quoted labels can span lines). It operates on `Character`s so that
/// columns and slicing stay correct for emoji and combining marks.
struct Scanner {
    private let chars: [Character]
    private(set) var index = 0
    private(set) var line: Int
    private(set) var column: Int

    init(_ text: some StringProtocol, at start: SourceLocation = .start) {
        chars = Array(text)
        line = start.line
        column = start.column
    }

    var isAtEnd: Bool { index >= chars.count }
    var location: SourceLocation { SourceLocation(line: line, column: column) }

    func peek(_ offset: Int = 0) -> Character? {
        let i = index + offset
        return i < chars.count ? chars[i] : nil
    }

    @discardableResult
    mutating func advance() -> Character? {
        guard index < chars.count else { return nil }
        let c = chars[index]
        index += 1
        if c == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        return c
    }

    mutating func advance(by count: Int) {
        for _ in 0..<count { advance() }
    }

    /// Skips spaces and tabs, and newlines too when `newlines` is true.
    mutating func skipWhitespace(newlines: Bool = false) {
        while let c = peek(), c == " " || c == "\t" || c == "\r" || (newlines && c == "\n") {
            advance()
        }
    }

    func hasPrefix(_ text: String, caseInsensitive: Bool = false) -> Bool {
        var i = index
        for expected in text {
            guard i < chars.count else { return false }
            let actual = chars[i]
            let matches = caseInsensitive
                ? actual.lowercased() == expected.lowercased()
                : actual == expected
            guard matches else { return false }
            i += 1
        }
        return true
    }

    /// Consumes `text` if it appears next.
    mutating func consume(_ text: String, caseInsensitive: Bool = false) -> Bool {
        guard hasPrefix(text, caseInsensitive: caseInsensitive) else { return false }
        advance(by: text.count)
        return true
    }

    /// Consumes `word` only when it is not immediately followed by another
    /// identifier character, so `end` does not match the start of `endpoint`.
    mutating func consumeKeyword(_ word: String, caseInsensitive: Bool = true) -> Bool {
        guard hasPrefix(word, caseInsensitive: caseInsensitive) else { return false }
        if let next = peek(word.count), next.isWordCharacter { return false }
        advance(by: word.count)
        return true
    }

    mutating func read(while predicate: (Character) -> Bool) -> String {
        var result = ""
        while let c = peek(), predicate(c) {
            result.append(c)
            advance()
        }
        return result
    }

    /// Reads up to (not including) the first occurrence of `terminator`.
    /// Returns nil and leaves the cursor untouched if it never appears.
    mutating func read(until terminator: String) -> String? {
        var probe = self
        var result = ""
        while !probe.isAtEnd {
            if probe.hasPrefix(terminator) {
                self = probe
                return result
            }
            result.append(probe.advance()!)
        }
        return nil
    }

    /// Reads the remainder of the current line and consumes the newline.
    mutating func readLine() -> String {
        let text = read { $0 != "\n" }
        advance()
        return text
    }

    mutating func expect(_ text: String, _ message: @autoclosure () -> String) throws {
        guard consume(text) else { throw MermaidError.syntax(message(), at: location) }
    }
}

extension Character {
    /// Letters, digits, and underscores: the characters that make up a word
    /// for keyword-boundary purposes.
    var isWordCharacter: Bool { isLetter || isNumber || self == "_" }
}
