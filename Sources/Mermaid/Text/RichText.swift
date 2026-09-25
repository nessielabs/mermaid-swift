/// Styled label text: lines made of spans with inline emphasis.
public struct RichText: Hashable, Sendable {
    public struct Span: Hashable, Sendable {
        public var text: String
        public var bold = false
        public var italic = false
        public var strikethrough = false
        public var code = false

        public init(_ text: String, bold: Bool = false, italic: Bool = false,
                    strikethrough: Bool = false, code: Bool = false) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.strikethrough = strikethrough
            self.code = code
        }

        func hasSameStyle(as other: Span) -> Bool {
            bold == other.bold && italic == other.italic
                && strikethrough == other.strikethrough && code == other.code
        }
    }

    public typealias Line = [Span]

    public var lines: [Line]
    /// Whether the author opted into automatic wrapping, which Mermaid
    /// enables for markdown strings.
    public var wraps: Bool

    public init(lines: [Line], wraps: Bool = false) {
        self.lines = lines.map(Self.coalesce)
        self.wraps = wraps
    }

    /// Unstyled text; newlines separate lines.
    public init(plain text: String) {
        self.init(lines: text.split(separator: "\n", omittingEmptySubsequences: false).map { [Span(String($0))] })
    }

    public static let empty = RichText(lines: [])

    public var isEmpty: Bool { lines.allSatisfy { $0.allSatisfy { $0.text.isEmpty } } }

    /// The text without styling, lines joined by newlines.
    public var plainText: String {
        lines.map { $0.map(\.text).joined() }.joined(separator: "\n")
    }

    private static func coalesce(_ line: Line) -> Line {
        var result: Line = []
        for span in line where !span.text.isEmpty {
            if let last = result.last, last.hasSameStyle(as: span) {
                result[result.count - 1].text += span.text
            } else {
                result.append(span)
            }
        }
        return result
    }
}
