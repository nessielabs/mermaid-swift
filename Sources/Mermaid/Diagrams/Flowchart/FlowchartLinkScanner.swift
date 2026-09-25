/// A link between node groups, as written in a flowchart statement.
struct FlowchartLinkToken: Equatable {
    var stroke: FlowchartDiagram.Link.Stroke
    var startMarker: Marker = .none
    var endMarker: Marker = .none
    var length = 1
    var label: String?
    var id: String?
}

/// Recognizes every flowchart link form: `-->`, `---`, `-.->`, `==>`,
/// `~~~`, longer variants that request more ranks, `o`/`x`/`<` markers at
/// either end, inline text (`-- text -->`, `-. text .->`, `== text ==>`),
/// pipe labels (`-->|text|`), and link ids (`e1@-->`).
enum FlowchartLinkScanner {
    static func scan(_ scanner: inout Scanner) throws -> FlowchartLinkToken? {
        var s = scanner
        var id: String?
        var probe = s
        let word = probe.read { $0.isWordCharacter }
        if !word.isEmpty, probe.consume("@"), let c = probe.peek(), "-=.~<ox".contains(c) {
            id = word
            s = probe
        }
        let location = s.location
        guard var token = try scanBody(&s) else { return nil }
        token.id = id
        var afterLink = s
        afterLink.skipWhitespace()
        if afterLink.consume("|") {
            guard let text = afterLink.read(until: "|") else {
                throw MermaidError.syntax("Link label is missing its closing '|'", at: location)
            }
            afterLink.advance()
            token.label = text.trimmingWhitespace().unquoted
            s = afterLink
        }
        scanner = s
        return token
    }

    private static func scanBody(_ s: inout Scanner) throws -> FlowchartLinkToken? {
        var start = Marker.none
        if s.peek() == "<" {
            start = .arrow
            s.advance()
        } else if let c = s.peek(), c == "o" || c == "x", let next = s.peek(1), "-=.".contains(next) {
            start = c == "o" ? .circle : .cross
            s.advance()
        }
        let location = s.location
        switch s.peek() {
        case "~":
            let count = s.read { $0 == "~" }.count
            guard count >= 3 else { return nil }
            return FlowchartLinkToken(stroke: .invisible, length: count - 2)
        case "=":
            return try runLink(&s, char: "=", stroke: .thick, start: start, location: location)
        case "-" where s.peek(1) == ".":
            s.advance()
            let dots = s.read { $0 == "." }.count
            if s.consume("-") {
                return FlowchartLinkToken(stroke: .dotted, startMarker: start, endMarker: head(&s) ?? .none, length: dots)
            }
            // `-. text .->`
            let text = try readText(&s, location: location) { probe in
                let closingDots = probe.read { $0 == "." }.count
                guard closingDots > 0, probe.consume("-") else { return nil }
                return (closingDots, head(&probe))
            }
            return FlowchartLinkToken(stroke: .dotted, startMarker: start, endMarker: text.head ?? .none,
                                      length: text.count, label: text.label)
        case "-":
            return try runLink(&s, char: "-", stroke: .normal, start: start, location: location)
        default:
            return nil
        }
    }

    /// Solid (`-`) and thick (`=`) links, with or without inline text.
    private static func runLink(_ s: inout Scanner, char: Character, stroke: FlowchartDiagram.Link.Stroke,
                                start: Marker, location: SourceLocation) throws -> FlowchartLinkToken? {
        var probe = s
        let count = probe.read { $0 == char }.count
        if count >= 2, let end = head(&probe) {
            s = probe
            return FlowchartLinkToken(stroke: stroke, startMarker: start, endMarker: end, length: count - 1)
        }
        if count >= 3 {
            s = probe
            return FlowchartLinkToken(stroke: stroke, startMarker: start, length: count - 2)
        }
        guard count == 2 else { return nil }
        s = probe
        let text = try readText(&s, location: location) { closing in
            let run = closing.read { $0 == char }.count
            if run >= 2, let end = head(&closing) { return (run - 1, end) }
            if run >= 3 { return (run - 2, nil) }
            return nil
        }
        return FlowchartLinkToken(stroke: stroke, startMarker: start, endMarker: text.head ?? .none,
                                  length: text.count, label: text.label)
    }

    /// Reads inline link text up to a closing pattern recognized by `closing`,
    /// which returns the closing run's length and optional end marker.
    private static func readText(_ s: inout Scanner, location: SourceLocation,
                                 closing: (inout Scanner) -> (Int, Marker?)?) throws
        -> (label: String, count: Int, head: Marker?) {
        var text = ""
        while let c = s.peek(), c != "\n" {
            if c == "\"" , text.trimmingWhitespace().isEmpty {
                var quoted = s
                quoted.advance()
                if let inner = quoted.read(until: "\"") {
                    quoted.advance()
                    text = inner
                    s = quoted
                    continue
                }
            }
            var probe = s
            if let (count, head) = closing(&probe) {
                s = probe
                return (text.trimmingWhitespace(), max(1, count), head)
            }
            text.append(c)
            s.advance()
        }
        throw MermaidError.syntax("Link text is missing its closing arrow", at: location)
    }

    /// An end marker, when one follows. `o` and `x` count only when not the
    /// start of a word, so `--x B` is a cross but `--xy` is not.
    private static func head(_ s: inout Scanner) -> Marker? {
        switch s.peek() {
        case ">": s.advance(); return .arrow
        case "o", "x":
            if let next = s.peek(1), next.isWordCharacter { return nil }
            let marker: Marker = s.peek() == "o" ? .circle : .cross
            s.advance()
            return marker
        default: return nil
        }
    }
}
