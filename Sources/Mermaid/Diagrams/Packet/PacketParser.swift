/// Parses packet source into a `PacketDiagram`.
///
/// Each statement is a field (`start: "label"`, `start-end: "label"`, or
/// `+count: "label"`) or a `title`. Fields must be contiguous, as mermaid.js
/// requires; a violation is reported at the offending number.
enum PacketParser {
    /// Bit positions beyond this are rejected so arithmetic cannot overflow.
    static let largestBit = 1 << 40

    static func parse(_ source: DiagramSource) throws -> PacketDiagram {
        var diagram = PacketDiagram()
        diagram.accessibility = source.accessibility
        guard source.headerArguments.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(source.headerArguments)' after 'packet'", at: source.header.location)
        }
        for line in source.lines {
            let text = line.textWithoutComment
            if let title = titleStatement(text) {
                diagram.title = title
                continue
            }
            let field = try parseField(text, line: line, next: diagram.bitCount)
            diagram.fields.append(field)
        }
        return diagram
    }

    /// The text of a `title` statement, which may be empty.
    static func titleStatement(_ text: String) -> String? {
        guard text.hasPrefix("title"), text.count == 5 || text.dropFirst(5).first?.isWhitespace == true else { return nil }
        return String(text.dropFirst(5)).trimmingWhitespace()
    }

    private static func parseField(_ text: String, line: SourceLine, next: Int) throws -> PacketDiagram.Field {
        var s = Scanner(text, at: line.location)
        let startLocation = s.location
        let start: Int, end: Int
        if s.consume("+") {
            s.skipWhitespace()
            let countLocation = s.location
            guard let count = s.readInteger(), count <= largestBit else {
                throw MermaidError.syntax("Expected a bit count after '+'", at: countLocation)
            }
            guard count > 0 else {
                throw MermaidError.semantic("Packet block \(next) is invalid. Cannot have a zero bit field.", at: countLocation)
            }
            start = next
            end = next + count - 1
        } else {
            guard let first = s.readInteger(), first <= largestBit else {
                throw MermaidError.syntax("Expected a bit range such as '0-15', a bit such as '7', or a count such as '+8'",
                                          at: startLocation)
            }
            s.skipWhitespace()
            if s.consume("-") {
                s.skipWhitespace()
                let endLocation = s.location
                guard let last = s.readInteger(), last <= largestBit else {
                    throw MermaidError.syntax("Expected the last bit of the range", at: endLocation)
                }
                guard last >= first else {
                    throw MermaidError.semantic("Packet block \(first) - \(last) is invalid. End must be greater than start.",
                                                at: endLocation)
                }
                end = last
            } else {
                end = first
            }
            start = first
            guard start == next else {
                throw MermaidError.semantic(
                    "Packet block \(start) - \(end) is not contiguous. It should start from \(next).", at: startLocation)
            }
        }
        s.skipWhitespace()
        try s.expect(":", "Expected ':' before the field label")
        s.skipWhitespace()
        let labelLocation = s.location
        guard let label = try s.readQuoted() else {
            throw MermaidError.syntax("Expected a quoted field label", at: labelLocation)
        }
        s.skipWhitespace()
        if let extra = s.peek() {
            throw MermaidError.syntax("Unexpected '\(extra)' after the field label", at: s.location)
        }
        return PacketDiagram.Field(start: start, end: end, label: label)
    }
}
