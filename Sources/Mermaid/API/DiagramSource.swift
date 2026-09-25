/// The body of a diagram handed to a diagram parser: its statements after
/// the header line, with shared statements (`accTitle`, `accDescr`)
/// already extracted.
struct DiagramSource: Sendable {
    /// The header statement, such as `flowchart LR`.
    var header: SourceLine
    /// Body statements after the header, in order, with original numbering.
    var lines: [SourceLine]
    /// The raw body text after the header, for character-level parsers,
    /// with extracted statements blanked so line numbers are unchanged.
    var text: String
    /// The line number the body text starts at.
    var textStartLine: Int
    var accessibility: Accessibility

    /// The text after the header keyword on the header line.
    var headerArguments: String {
        String(header.text.drop { !$0.isWhitespace }).trimmingWhitespace()
    }

    init(prepared: PreparedSource, header: SourceLine) {
        self.header = header
        var bodyLines = prepared.body.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        // Drop everything through the header line.
        for i in 0..<min(header.number, bodyLines.count) { bodyLines[i] = "" }
        var accessibility = Accessibility()
        var i = header.number
        while i < bodyLines.count {
            let trimmed = bodyLines[i].trimmingWhitespace()
            if let value = Self.value(of: "accTitle", in: trimmed) {
                accessibility.title = value
                bodyLines[i] = ""
            } else if let value = Self.value(of: "accDescr", in: trimmed) {
                accessibility.description = value
                bodyLines[i] = ""
            } else if trimmed.hasPrefix("accDescr"), trimmed.dropFirst(8).trimmingWhitespace().hasPrefix("{") {
                var parts = [String(trimmed.drop { $0 != "{" }.dropFirst())]
                bodyLines[i] = ""
                while !(parts.last ?? "").contains("}"), i + 1 < bodyLines.count {
                    i += 1
                    parts.append(bodyLines[i])
                    bodyLines[i] = ""
                }
                let joined = parts.joined(separator: "\n")
                accessibility.description = String(joined.prefix { $0 != "}" }).trimmingWhitespace()
            }
            i += 1
        }
        self.accessibility = accessibility
        text = bodyLines.joined(separator: "\n")
        textStartLine = 1
        lines = SourceLine.split(text)
    }

    private static func value(of keyword: String, in line: String) -> String? {
        guard line.hasPrefix(keyword) else { return nil }
        let rest = line.dropFirst(keyword.count).trimmingWhitespace()
        guard rest.hasPrefix(":") else { return nil }
        return String(rest.dropFirst()).trimmingWhitespace()
    }
}
