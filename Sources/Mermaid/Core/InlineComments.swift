extension StringProtocol {
    /// The text before a trailing `%%` comment, ignoring `%%` inside single
    /// or double quotes, with trailing whitespace removed. Line-oriented
    /// chart grammars (pie, quadrant, XY, radar) accept such comments
    /// after a statement; whole-line comments are already dropped by
    /// `SourceLine.split`.
    func strippingInlineComment() -> String {
        var quote: Character?
        var previous: Character?
        var end = endIndex
        for index in indices {
            let c = self[index]
            if let open = quote {
                if c == open { quote = nil }
            } else if c == "\"" || c == "'" {
                quote = c
            } else if c == "%", previous == "%" {
                end = self.index(before: index)
                break
            }
            previous = c
        }
        return String(self[..<end]).trimmingWhitespace()
    }
}
