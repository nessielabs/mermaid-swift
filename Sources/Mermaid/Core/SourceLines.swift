import Foundation


/// One logical line of diagram source, with its original line number.
struct SourceLine: Hashable, Sendable {
    /// The 1-based line number in the original source.
    var number: Int
    /// The line with leading and trailing whitespace removed.
    var text: String
    /// The count of leading whitespace columns (tabs count as four).
    var indent: Int

    var location: SourceLocation { SourceLocation(line: number, column: indent + 1) }

    /// The location of a column offset within `text`.
    func location(atOffset offset: Int) -> SourceLocation {
        SourceLocation(line: number, column: indent + 1 + offset)
    }
}

extension SourceLine {
    /// Splits text into trimmed lines, dropping blank lines and `%%`
    /// comments while preserving original line numbers.
    static func split(_ text: String, firstLine: Int = 1) -> [SourceLine] {
        var lines: [SourceLine] = []
        var number = firstLine
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            defer { number += 1 }
            var indent = 0
            for c in raw {
                if c == " " { indent += 1 } else if c == "\t" { indent += 4 } else { break }
            }
            let trimmed = raw.trimmingWhitespace()
            guard !trimmed.isEmpty, !trimmed.hasPrefix("%%") else { continue }
            lines.append(SourceLine(number: number, text: trimmed, indent: indent))
        }
        return lines
    }
}

extension StringProtocol {
    /// The string without leading or trailing spaces, tabs, and newlines.
    func trimmingWhitespace() -> String {
        let isSpace: (Character) -> Bool = { $0 == " " || $0 == "\t" || $0 == "\r" || $0 == "\n" }
        guard let start = firstIndex(where: { !isSpace($0) }) else { return "" }
        let end = lastIndex(where: { !isSpace($0) })!
        return String(self[start...end])
    }

    /// The text without one pair of surrounding double quotes, if present.
    var unquoted: String {
        guard count >= 2, hasPrefix("\""), hasSuffix("\"") else { return String(self) }
        return String(dropFirst().dropLast())
    }

    /// Splits once at the first occurrence of `separator`.
    func splitOnce(_ separator: String) -> (String, String)? {
        guard let range = range(of: separator) else { return nil }
        return (String(self[..<range.lowerBound]), String(self[range.upperBound...]))
    }
}
