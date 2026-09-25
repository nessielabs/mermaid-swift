/// Recognizes the arrow of a sequence message, such as `->>` or `--x`.
enum SequenceArrowScanner {
    struct Arrow: Hashable {
        var token: String
        var line: SequenceDiagram.LineStyle
        var tail: SequenceDiagram.ArrowHead
        var head: SequenceDiagram.ArrowHead
    }

    /// Every arrow mermaid.js accepts, longest first so that `-->>` wins
    /// over `-->` and `->`.
    static let arrows: [Arrow] = {
        typealias H = SequenceDiagram.ArrowHead
        var list: [Arrow] = [
            Arrow(token: "<<-->>", line: .dotted, tail: .arrow, head: .arrow),
            Arrow(token: "<<->>", line: .solid, tail: .arrow, head: .arrow),
            Arrow(token: "-->>", line: .dotted, tail: .none, head: .arrow),
            Arrow(token: "->>", line: .solid, tail: .none, head: .arrow),
            Arrow(token: "-->", line: .dotted, tail: .none, head: .none),
            Arrow(token: "->", line: .solid, tail: .none, head: .none),
            Arrow(token: "--x", line: .dotted, tail: .none, head: .cross),
            Arrow(token: "-x", line: .solid, tail: .none, head: .cross),
            Arrow(token: "--)", line: .dotted, tail: .none, head: .async),
            Arrow(token: "-)", line: .solid, tail: .none, head: .async),
        ]
        // Half arrows (v11.12.3): `|\` and `\\` put the barb on top, `|/`
        // and `//` below; written before the dashes they decorate the tail.
        let halves: [(String, H)] = [("|\\", .halfTop), ("|/", .halfBottom), ("\\\\", .stickTop), ("//", .stickBottom)]
        let reversed: [(String, H)] = [("/|", .halfTop), ("\\|", .halfBottom), ("//", .stickTop), ("\\\\", .stickBottom)]
        for (dashes, line) in [("--", SequenceDiagram.LineStyle.dotted), ("-", .solid)] {
            for (glyph, head) in halves { list.append(Arrow(token: dashes + glyph, line: line, tail: .none, head: head)) }
            for (glyph, tail) in reversed { list.append(Arrow(token: glyph + dashes, line: line, tail: tail, head: .none)) }
        }
        return list.sorted { $0.token.count > $1.token.count }
    }()

    /// The arrow starting at `offset` in `chars`, matching `x` case-insensitively.
    static func arrow(in chars: [Character], at offset: Int) -> Arrow? {
        arrows.first { arrow in
            guard offset + arrow.token.count <= chars.count else { return false }
            for (k, expected) in arrow.token.enumerated() {
                let actual: Character = chars[offset + k]
                let matches: Bool = expected == "x" ? (actual == "x" || actual == "X") : expected == actual
                if !matches { return false }
            }
            return true
        }
    }

    /// The parts of a signal's left-hand side: `A->>+B` or `A()-x()B`.
    struct Signal: Hashable {
        var source: String
        var target: String
        var arrow: Arrow
        /// Column offsets of the source, the arrow, and the target within the text.
        var sourceOffset: Int
        var arrowOffset: Int
        var targetOffset: Int
        var activate = false
        var deactivate = false
        var centralSource = false
        var centralTarget = false
    }

    /// Splits `text` (without its `: message` part) at its arrow.
    ///
    /// Participant names may contain dashes, so a name like `auth-xyz`
    /// holds an arrow-like `-x`. Every split is considered and the one
    /// leaving the fewest arrow-like tokens in the names wins, then the
    /// longer arrow, then the earlier one; mermaid.js would split at the
    /// first arrow-like token.
    static func signal(in text: String) -> Signal? {
        let chars = Array(text)
        let candidates = chars.indices.compactMap { candidate(in: chars, at: $0) }
        return candidates.min { a, b in
            if a.ambiguity != b.ambiguity { return a.ambiguity < b.ambiguity }
            if a.signal.arrow.token.count != b.signal.arrow.token.count {
                return a.signal.arrow.token.count > b.signal.arrow.token.count
            }
            return a.signal.arrowOffset < b.signal.arrowOffset
        }?.signal
    }

    private static func candidate(in chars: [Character], at offset: Int) -> (signal: Signal, ambiguity: Int)? {
        guard offset > 0, let arrow = arrow(in: chars, at: offset) else { return nil }
        var signal = Signal(source: "", target: "", arrow: arrow, sourceOffset: 0, arrowOffset: offset, targetOffset: 0)
        var source = String(chars[..<offset]).trimmingWhitespace()
        if source.hasSuffix("()") {
            signal.centralSource = true
            source = String(source.dropLast(2)).trimmingWhitespace()
        }
        var index = offset + arrow.token.count
        func skipSpaces() { while index < chars.count, chars[index] == " " || chars[index] == "\t" { index += 1 } }
        skipSpaces()
        if index + 1 < chars.count, chars[index] == "(", chars[index + 1] == ")" {
            signal.centralTarget = true
            index += 2
        } else if index < chars.count, chars[index] == "+" {
            signal.activate = true
            index += 1
        } else if index < chars.count, chars[index] == "-" {
            signal.deactivate = true
            index += 1
        }
        skipSpaces()
        let target = String(chars[index...]).trimmingWhitespace()
        guard !source.isEmpty, !target.isEmpty, !target.contains(where: { "+<>".contains($0) }) else { return nil }
        signal.source = source
        signal.target = target
        signal.sourceOffset = chars.prefix { $0 == " " || $0 == "\t" }.count
        signal.targetOffset = index
        return (signal, arrowCount(source) + arrowCount(target))
    }

    private static func arrowCount(_ text: String) -> Int {
        let chars = Array(text)
        return chars.indices.filter { arrow(in: chars, at: $0) != nil }.count
    }
}
