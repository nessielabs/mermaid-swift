extension StringProtocol {
    /// The statements on one line of a chart grammar (quadrant, XY): the
    /// line is cut at a trailing `%%` comment and split at `;` separators
    /// outside double quotes. Each statement is trimmed and reported with
    /// its column offset in the line; empty statements are dropped.
    func chartStatements() -> [(text: String, offset: Int)] {
        let text = strippingInlineComment()
        var result: [(String, Int)] = []
        var current = "", start = 0, offset = 0, quoted = false
        for c in text {
            if c == "\"" { quoted.toggle() }
            if c == ";", !quoted {
                result.append((current, start))
                current = ""
                start = offset + 1
            } else {
                current.append(c)
            }
            offset += 1
        }
        result.append((current, start))
        return result.compactMap { text, start in
            let leading = text.prefix { $0 == " " || $0 == "\t" }.count
            let trimmed = text.trimmingWhitespace()
            return trimmed.isEmpty ? nil : (trimmed, start + leading)
        }
    }
}
