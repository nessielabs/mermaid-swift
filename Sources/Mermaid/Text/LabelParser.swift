import Foundation

/// Converts raw label source into `RichText`.
///
/// Mermaid labels come in two dialects:
/// - Markdown strings, written inside backticks: `**bold**`, `*italic*`
///   or `_italic_`, `~~strike~~`, real newlines as line breaks, and
///   automatic wrapping.
/// - Everything else, which may contain `<br>` line breaks, a small set of
///   inline HTML tags, HTML entities, and Mermaid's `#name;`/`#123;`
///   entity codes. Unknown tags are dropped and Font Awesome icon tokens
///   (`fa:fa-car`), which need an icon font, are removed.
public enum LabelParser {
    public static func parse(_ raw: String) -> RichText {
        let trimmed = raw.trimmingWhitespace()
        if trimmed.count >= 2, trimmed.hasPrefix("`"), trimmed.hasSuffix("`") {
            return parseMarkdown(String(trimmed.dropFirst().dropLast()))
        }
        return parseHTML(raw)
    }

    // MARK: - Markdown strings

    static func parseMarkdown(_ text: String) -> RichText {
        let rawLines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let indent = rawLines.filter { !$0.trimmingWhitespace().isEmpty }
            .map { $0.prefix { $0 == " " || $0 == "\t" }.count }.min() ?? 0
        let lines = rawLines.map { parseInlineMarkdown(String($0.dropFirst(min(indent, $0.count))).trimmingWhitespace()) }
        return RichText(lines: trimBlankEdges(lines), wraps: true)
    }

    private static func parseInlineMarkdown(_ text: String) -> RichText.Line {
        var spans: RichText.Line = []
        var style = RichText.Span("")
        var buffer = ""
        let chars = Array(text)
        var i = 0
        func flush() {
            guard !buffer.isEmpty else { return }
            var span = style
            span.text = buffer
            spans.append(span)
            buffer = ""
        }
        func closes(_ marker: String, from index: Int) -> Bool {
            String(chars[index...]).range(of: marker) != nil
        }
        while i < chars.count {
            let rest = String(chars[i...])
            if rest.hasPrefix("**") || rest.hasPrefix("__"), style.bold || closes(String(rest.prefix(2)), from: i + 2) {
                flush(); style.bold.toggle(); i += 2
            } else if rest.hasPrefix("~~"), style.strikethrough || closes("~~", from: i + 2) {
                flush(); style.strikethrough.toggle(); i += 2
            } else if chars[i] == "*" || chars[i] == "_", style.italic || closes(String(chars[i]), from: i + 1) {
                flush(); style.italic.toggle(); i += 1
            } else {
                buffer.append(chars[i]); i += 1
            }
        }
        flush()
        return spans
    }

    // MARK: - HTML-ish labels

    static func parseHTML(_ text: String) -> RichText {
        // Leniency beyond mermaid.js: generated diagrams often write a literal
        // `\n` expecting a line break (mermaid.js prints it verbatim).
        let text = removeIcons(decodeMermaidEntities(text)).replacingOccurrences(of: "\\n", with: "\n")
        var lines: [RichText.Line] = [[]]
        var style = RichText.Span("")
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "<", let close = text[index...].firstIndex(of: ">"),
               case let tag = text[text.index(after: index)..<close].lowercased(),
               case let name = String(tag.drop { $0 == "/" }.prefix { $0.isLetter }),
               Self.htmlTags.contains(name) {
                let isClosing = tag.hasPrefix("/")
                switch name {
                case "br": lines.append([])
                case "b", "strong": style.bold = !isClosing
                case "i", "em": style.italic = !isClosing
                case "s", "del", "strike": style.strikethrough = !isClosing
                case "code": style.code = !isClosing
                case "p", "div": if isClosing { lines.append([]) }
                default: break
                }
                index = text.index(after: close)
                continue
            }
            let next = text[index...].firstIndex(of: "<").map { $0 == index ? text.index(after: index) : $0 } ?? text.endIndex
            let chunk = decodeHTMLEntities(String(text[index..<next]))
            let parts = chunk.split(separator: "\n", omittingEmptySubsequences: false)
            for (n, part) in parts.enumerated() {
                if n > 0 { lines.append([]) }
                append(String(part), to: &lines, style: style)
            }
            index = next
        }
        return RichText(lines: trimBlankEdges(lines))
    }

    /// Tag names treated as markup; anything else after `<` is literal text.
    private static let htmlTags: Set<String> = [
        "a", "abbr", "b", "big", "br", "code", "del", "div", "em", "font", "i", "img", "ins", "kbd",
        "mark", "p", "q", "s", "small", "span", "strike", "strong", "sub", "sup", "u",
    ]

    private static func append(_ text: String, to lines: inout [RichText.Line], style: RichText.Span) {
        var span = style
        span.text = text
        lines[lines.count - 1].append(span)
    }

    private static func trimBlankEdges(_ lines: [RichText.Line]) -> [RichText.Line] {
        var lines = lines
        let isBlank: (RichText.Line) -> Bool = { $0.allSatisfy { $0.text.trimmingWhitespace().isEmpty } }
        while let first = lines.first, isBlank(first), lines.count > 1 { lines.removeFirst() }
        while let last = lines.last, isBlank(last), lines.count > 1 { lines.removeLast() }
        return lines
    }
}
