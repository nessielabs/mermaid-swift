extension Scanner {
    /// Reads a string literal delimited by double or single quotes and
    /// returns its contents without the quotes. Backslash escapes the next
    /// character, as in Mermaid's Langium `STRING` terminal.
    ///
    /// Returns nil without consuming anything when no quote comes next, and
    /// throws a located error when the literal is never closed. Literals
    /// may span lines only when `multiline` is set.
    mutating func readQuoted(multiline: Bool = false) throws -> String? {
        guard let quote = peek(), quote == "\"" || quote == "'" else { return nil }
        let location = self.location
        var probe = self
        probe.advance()
        var text = ""
        while let c = probe.peek(), multiline || c != "\n" {
            probe.advance()
            if c == quote {
                self = probe
                return text
            }
            if c == "\\", let next = probe.peek(), next == quote || next == "\\" {
                probe.advance()
                text.append(next)
            } else {
                text.append(c)
            }
        }
        throw MermaidError.syntax("String is missing its closing \(quote)", at: location)
    }

    /// Reads an unsigned decimal integer, or returns nil when no digit comes next.
    mutating func readInteger() -> Int? {
        let digits = read { $0.isASCII && $0.isNumber }
        return digits.isEmpty ? nil : Int(digits)
    }
}

extension SourceLine {
    /// The line with a trailing `%%` comment removed. Comment markers inside
    /// quoted strings are kept, so `"50%% off"` survives.
    var textWithoutComment: String {
        var quote: Character?
        var previous: Character?
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            if let q = quote {
                if c == q { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "%", previous == "%" {
                return String(text[..<text.index(before: index)]).trimmingWhitespace()
            }
            previous = c
            index = text.index(after: index)
        }
        return text
    }
}
