/// Rich text laid out into measured lines, ready to position and draw.
public struct TextBlock: Hashable, Sendable {
    public struct Run: Hashable, Sendable {
        public var text: String
        public var font: Font
        /// Horizontal offset from the start of the line.
        public var x: Double
        public var width: Double
        public var strikethrough: Bool
    }

    public struct Line: Hashable, Sendable {
        public var runs: [Run]
        public var width: Double
        /// Baseline offset from the top of the block.
        public var baseline: Double
    }

    public var lines: [Line]
    public var width: Double
    public var height: Double

    public static let empty = TextBlock(lines: [], width: 0, height: 0)

    public var isEmpty: Bool { lines.isEmpty }
}

extension TextBlock {
    /// Lays out `text` in `font`, wrapping at `maxWidth` when the text asks
    /// for wrapping or when `forceWrap` is set.
    public init(_ text: RichText, font: Font, measurer: any TextMeasurer,
                maxWidth: Double? = nil, forceWrap: Bool = false) {
        let limit = (text.wraps || forceWrap) ? maxWidth : nil
        let metrics = measurer.metrics(for: font)
        let lineHeight = max(font.lineHeight, (metrics.ascent + metrics.descent).rounded(.up))
        let baselineOffset = (lineHeight - metrics.ascent - metrics.descent) / 2 + metrics.ascent

        var lines: [Line] = []
        for sourceLine in text.lines {
            for runs in Self.wrap(sourceLine, font: font, measurer: measurer, limit: limit) {
                let width = runs.last.map { $0.x + $0.width } ?? 0
                lines.append(Line(runs: runs, width: width,
                                  baseline: Double(lines.count) * lineHeight + baselineOffset))
            }
        }
        self.lines = lines
        width = lines.map(\.width).max() ?? 0
        height = Double(lines.count) * lineHeight
    }

    /// Greedy word wrap. Words longer than the limit break by character.
    private static func wrap(_ spans: RichText.Line, font: Font, measurer: any TextMeasurer,
                             limit: Double?) -> [[Run]] {
        var lines: [[Run]] = [[]]
        var x = 0.0
        func place(_ text: String, _ runFont: Font, _ span: RichText.Span) {
            let w = measurer.width(of: text, font: runFont)
            if var last = lines[lines.count - 1].last, last.font == runFont,
               last.strikethrough == span.strikethrough {
                last.text += text
                last.width += w
                lines[lines.count - 1][lines[lines.count - 1].count - 1] = last
            } else {
                lines[lines.count - 1].append(Run(text: text, font: runFont, x: x, width: w,
                                                  strikethrough: span.strikethrough))
            }
            x += w
        }
        func newLine() {
            if var last = lines[lines.count - 1].last, last.text.hasSuffix(" ") {
                let trimmed = String(last.text.reversed().drop { $0 == " " }.reversed())
                last.width = measurer.width(of: trimmed, font: last.font)
                last.text = trimmed
                lines[lines.count - 1][lines[lines.count - 1].count - 1] = last
            }
            lines.append([])
            x = 0
        }
        for span in spans {
            let runFont = font.styled(for: span)
            guard let limit else { place(span.text, runFont, span); continue }
            for word in words(in: span.text) {
                let w = measurer.width(of: word, font: runFont)
                if x + w > limit, x > 0, !word.allSatisfy({ $0 == " " }) { newLine() }
                if x == 0, word.allSatisfy({ $0 == " " }) { continue }
                if w <= limit {
                    place(word, runFont, span)
                    continue
                }
                for c in word {
                    let cw = measurer.width(of: String(c), font: runFont)
                    if x + cw > limit, x > 0 { newLine() }
                    place(String(c), runFont, span)
                }
            }
        }
        return lines
    }

    /// Splits text into words and whitespace runs, preserving both.
    private static func words(in text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for c in text {
            if let last = current.last, (last == " ") != (c == " ") {
                result.append(current)
                current = ""
            }
            current.append(c)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }
}
