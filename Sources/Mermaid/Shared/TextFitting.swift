/// Fits a label into a fixed box by wrapping it and, when wrapping is not
/// enough, stepping the font size down.
///
/// Diagrams whose shapes are sized by data rather than by their labels
/// (treemap cells, packet fields) use this so text never spills out of the
/// shape it describes.
struct TextFitting {
    var measurer: any TextMeasurer
    var font: Font
    /// The smallest font size worth drawing.
    var minimumSize: Double
    /// How much to shrink the font per attempt.
    var step: Double = 1

    /// The largest rendition of `text` no bigger than `box`, wrapped at word
    /// boundaries, or nil when even the minimum size does not fit.
    func fit(_ text: RichText, in box: Size) -> TextBlock? {
        guard box.width > 0, box.height > 0, !text.isEmpty else { return nil }
        var size = font.size
        var fallback: TextBlock?
        while size >= minimumSize {
            let candidate = TextBlock(text, font: font.withSize(size), measurer: measurer,
                                      maxWidth: box.width, forceWrap: true)
            if candidate.width <= box.width + 0.01, candidate.height <= box.height + 0.01 {
                if !Self.breaksWords(candidate, of: text) { return candidate }
                fallback = fallback ?? candidate
            }
            size -= step
        }
        return fallback
    }

    /// Like `fit`, but keeps the text on one line, shortening it with an
    /// ellipsis when it is too wide. Returns nil when nothing legible fits.
    func fitSingleLine(_ text: String, width: Double, height: Double = .infinity) -> TextBlock? {
        guard width > 0 else { return nil }
        var size = font.size
        while size >= minimumSize {
            let sized = font.withSize(size)
            if sized.lineHeight <= height + 0.01 {
                if measurer.width(of: text, font: sized) <= width {
                    return TextBlock(RichText(plain: text), font: sized, measurer: measurer)
                }
                if size - step < minimumSize { return Self.truncated(text, font: sized, width: width, measurer: measurer) }
            }
            size -= step
        }
        return nil
    }

    /// `text` shortened with a trailing ellipsis to fit `width`.
    static func truncated(_ text: String, font: Font, width: Double, measurer: any TextMeasurer) -> TextBlock? {
        var characters = Array(text)
        while !characters.isEmpty {
            characters.removeLast()
            let candidate = String(characters).trimmingWhitespace() + "…"
            if measurer.width(of: candidate, font: font) <= width {
                return TextBlock(RichText(plain: candidate), font: font, measurer: measurer)
            }
        }
        return nil
    }

    /// Whether wrapping had to split a word across lines, which reads badly;
    /// a smaller font is preferred in that case.
    private static func breaksWords(_ block: TextBlock, of text: RichText) -> Bool {
        let words = Set(text.plainText.split(whereSeparator: { $0 == " " || $0 == "\n" }).map(String.init))
        let pieces = block.lines.flatMap { line in
            line.runs.map(\.text).joined().split(separator: " ").map(String.init)
        }
        return pieces.contains { !words.contains($0) }
    }
}
