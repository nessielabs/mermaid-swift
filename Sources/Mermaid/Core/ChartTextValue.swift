extension StringProtocol {
    /// A text value in the chart grammars (quadrant, XY): surrounding
    /// whitespace is dropped, a `"quoted string"` loses its quotes, and a
    /// markdown string ``"`**bold**`"`` keeps only its backticks so that
    /// `LabelParser` renders it as markdown.
    var chartTextValue: String {
        let text = trimmingWhitespace()
        if text.count >= 4, text.hasPrefix("\"`"), text.hasSuffix("`\"") {
            return String(text.dropFirst().dropLast())
        }
        return text.unquoted
    }
}
