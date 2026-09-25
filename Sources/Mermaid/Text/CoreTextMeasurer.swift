#if canImport(CoreText)
import CoreText
import Foundation

/// Resolves `Font` requests to CoreText fonts, honoring the CSS family
/// list in order and falling back to the system font. Results are cached;
/// the resolver is safe to share across threads.
public final class FontResolver: @unchecked Sendable {
    public static let shared = FontResolver()

    private let lock = NSLock()
    private var cache: [Font: CTFont] = [:]

    public init() {}

    public func ctFont(for font: Font) -> CTFont {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[font] { return cached }
        let resolved = resolve(font)
        cache[font] = resolved
        return resolved
    }

    private func resolve(_ font: Font) -> CTFont {
        let size = CGFloat(font.size)
        var base: CTFont?
        if font.monospaced {
            base = CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
        } else {
            for family in Self.families(in: font.family) {
                if let match = Self.font(named: family, size: size) {
                    base = match
                    break
                }
            }
        }
        let resolved = base ?? CTFontCreateUIFontForLanguage(.system, size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, size, nil)
        var traits = CTFontSymbolicTraits()
        if font.bold { traits.insert(.traitBold) }
        if font.italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return resolved }
        return CTFontCreateCopyWithSymbolicTraits(resolved, size, nil, traits, traits) ?? resolved
    }

    static func families(in list: String) -> [String] {
        list.split(separator: ",").map {
            $0.trimmingWhitespace().trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }.filter { !$0.isEmpty }
    }

    private static func font(named family: String, size: CGFloat) -> CTFont? {
        switch family.lowercased() {
        case "sans-serif", "system-ui", "-apple-system", "blinkmacsystemfont", "ui-sans-serif":
            return CTFontCreateUIFontForLanguage(.system, size, nil)
        case "monospace", "ui-monospace":
            return CTFontCreateUIFontForLanguage(.userFixedPitch, size, nil)
        case "serif", "ui-serif":
            return CTFontCreateWithName("Times New Roman" as CFString, size, nil)
        default:
            // CoreText substitutes a default font for unknown names, so accept
            // the result only when the family actually matches.
            let candidate = CTFontCreateWithName(family as CFString, size, nil)
            let resolvedFamily = CTFontCopyFamilyName(candidate) as String
            return resolvedFamily.caseInsensitiveCompare(family) == .orderedSame ? candidate : nil
        }
    }
}

/// Measures text with CoreText using the fonts `FontResolver` selects, so
/// measurements match what the CoreGraphics renderer draws.
public struct CoreTextMeasurer: TextMeasurer {
    private let resolver: FontResolver

    public init(resolver: FontResolver = .shared) {
        self.resolver = resolver
    }

    public func width(of text: String, font: Font) -> Double {
        guard !text.isEmpty else { return 0 }
        let attributes = [kCTFontAttributeName as NSAttributedString.Key: resolver.ctFont(for: font)]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        return Double(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    public func metrics(for font: Font) -> FontMetrics {
        let ctFont = resolver.ctFont(for: font)
        return FontMetrics(ascent: Double(CTFontGetAscent(ctFont)), descent: Double(CTFontGetDescent(ctFont)))
    }
}
#endif

/// The measurer used when none is specified: CoreText where available,
/// otherwise the deterministic approximation.
public func defaultTextMeasurer() -> any TextMeasurer {
    #if canImport(CoreText)
    return CoreTextMeasurer()
    #else
    return ApproximateTextMeasurer()
    #endif
}
