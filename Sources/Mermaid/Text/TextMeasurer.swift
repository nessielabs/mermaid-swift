/// A font request: a CSS-style family list plus size and style.
public struct Font: Hashable, Sendable {
    /// A CSS font-family list, such as `"trebuchet ms", verdana, sans-serif`.
    public var family: String
    public var size: Double
    public var bold: Bool
    public var italic: Bool
    public var monospaced: Bool

    public init(family: String = Theme.defaultFontFamily, size: Double = 16,
                bold: Bool = false, italic: Bool = false, monospaced: Bool = false) {
        self.family = family
        self.size = size
        self.bold = bold
        self.italic = italic
        self.monospaced = monospaced
    }

    func styled(for span: RichText.Span) -> Font {
        var font = self
        font.bold = bold || span.bold
        font.italic = italic || span.italic
        font.monospaced = monospaced || span.code
        return font
    }

    func withSize(_ size: Double) -> Font {
        var font = self
        font.size = size
        return font
    }

    /// The distance between baselines of consecutive lines.
    var lineHeight: Double { (size * 1.25).rounded() }
}

/// Vertical font metrics, in points.
public struct FontMetrics: Hashable, Sendable {
    public var ascent: Double
    public var descent: Double

    public init(ascent: Double, descent: Double) {
        self.ascent = ascent
        self.descent = descent
    }
}

/// Measures text so that layout can size shapes around labels.
///
/// Rendering must measure with the same fonts it draws with, or labels
/// overflow their shapes. `CoreTextMeasurer` does that on Apple
/// platforms; `ApproximateTextMeasurer` gives deterministic, font-free
/// results for tests and for platforms without CoreText.
public protocol TextMeasurer: Sendable {
    func width(of text: String, font: Font) -> Double
    func metrics(for font: Font) -> FontMetrics
}

/// Estimates widths from per-character classes of a typical sans-serif
/// font. Deterministic across machines.
public struct ApproximateTextMeasurer: TextMeasurer {
    public init() {}

    public func width(of text: String, font: Font) -> Double {
        let em = text.reduce(0.0) { $0 + (font.monospaced ? 0.6 : Self.advance(of: $1)) }
        return em * font.size * (font.bold ? 1.06 : 1)
    }

    public func metrics(for font: Font) -> FontMetrics {
        FontMetrics(ascent: font.size * 0.8, descent: font.size * 0.2)
    }

    static func advance(of c: Character) -> Double {
        if c == " " { return 0.28 }
        if "iljtfI!|.,:;'`".contains(c) { return 0.3 }
        if "mwMW@%".contains(c) { return 0.86 }
        if c.isUppercase { return 0.66 }
        if c.isNumber { return 0.56 }
        if let scalar = c.unicodeScalars.first,
           scalar.properties.isEmojiPresentation || (0x2E80...0x9FFF).contains(scalar.value)
            || (0xAC00...0xD7AF).contains(scalar.value) || (0xFF00...0xFFEF).contains(scalar.value) {
            return 1.0
        }
        return 0.52
    }
}
