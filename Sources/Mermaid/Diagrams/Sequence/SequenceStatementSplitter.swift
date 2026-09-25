/// One `;`- or newline-separated statement of a sequence diagram.
struct SequenceStatementText: Hashable {
    var text: String
    var line: SourceLine
    /// The column offset of `text` within `line.text`.
    var offset: Int

    var location: SourceLocation { line.location(atOffset: offset) }

    func location(at column: Int) -> SourceLocation { line.location(atOffset: offset + column) }
}

enum SequenceStatementSplitter {
    /// Splits source lines into statements.
    ///
    /// A `;` ends a statement unless it closes an entity code such as
    /// `#59;` or `&amp;`, which is how mermaid.js lets messages contain
    /// semicolons. Leniently, a `;` followed by text that cannot start a
    /// statement (`A->>B: look up key; check hash`) is kept as text where
    /// mermaid.js would fail. A `%%` starts a comment that runs to the end
    /// of the line.
    static func split(_ lines: [SourceLine]) -> [SequenceStatementText] {
        var statements: [SequenceStatementText] = []
        for line in lines {
            let chars = Array(line.text)
            var start = 0
            var i = 0
            func flush(until end: Int) {
                let raw = String(chars[start..<end])
                let leading = raw.prefix { $0 == " " || $0 == "\t" }.count
                let text = raw.trimmingWhitespace()
                if !text.isEmpty {
                    statements.append(SequenceStatementText(text: text, line: line, offset: start + leading))
                }
            }
            while i < chars.count {
                if chars[i] == "%", i + 1 < chars.count, chars[i + 1] == "%" {
                    break
                }
                if chars[i] == ";", !closesEntity(chars, at: i),
                   startsStatement(String(chars[(i + 1)...]).trimmingWhitespace()) {
                    flush(until: i)
                    start = i + 1
                }
                i += 1
            }
            flush(until: i)
        }
        return statements
    }

    /// Whether text looks like the start of a statement: a keyword, a
    /// message, or nothing at all.
    static func startsStatement(_ text: String) -> Bool {
        let text = text.hasPrefix("%%") ? "" : text
        guard !text.isEmpty else { return true }
        if let (keyword, _, _) = SequenceParser.keyword(in: text), SequenceParser.keywords.contains(keyword) { return true }
        return SequenceArrowScanner.signal(in: text.splitOnce(":")?.0 ?? text) != nil
    }

    /// Whether the `;` at `index` terminates `#name`, `#123`, `&name` or `&#x1F;`.
    private static func closesEntity(_ chars: [Character], at index: Int) -> Bool {
        var j = index - 1
        while j >= 0, chars[j].isLetter || chars[j].isNumber { j -= 1 }
        guard j < index - 1, j >= 0 else { return false }
        return chars[j] == "#" || chars[j] == "&"
    }
}
