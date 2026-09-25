/// Parses `sankey` and `sankey-beta` source: CSV rows of
/// `source,target,value` after the header.
///
/// The CSV dialect is RFC 4180 as mermaid.js implements it: exactly three
/// fields per row, fields may be double-quoted (a quoted field may contain
/// commas, newlines and `""` for a quote), and blank lines are allowed.
/// Node names are trimmed. Values must be non-negative numbers, and the
/// links may not form a cycle, which d3-sankey cannot lay out.
enum SankeyParser {
    static func parse(_ source: DiagramSource) throws -> SankeyDiagram {
        var diagram = SankeyDiagram()
        diagram.accessibility = source.accessibility
        let arguments = source.headerArguments.trimmingWhitespace()
        guard arguments.isEmpty else {
            let offset = source.header.text.count - source.headerArguments.count
            throw MermaidError.syntax("Unexpected '\(arguments)' after the sankey header; rows go on the following lines",
                                      at: source.header.location(atOffset: offset))
        }
        var scanner = Scanner(source.text)
        while !scanner.isAtEnd {
            scanner.skipWhitespace()
            if scanner.peek() == "\n" { scanner.advance(); continue }
            if scanner.isAtEnd { break }
            try row(&scanner, into: &diagram)
        }
        try rejectCycles(diagram)
        return diagram
    }

    private static func row(_ scanner: inout Scanner, into diagram: inout SankeyDiagram) throws {
        let location = scanner.location
        var fields: [(text: String, location: SourceLocation)] = []
        while true {
            let fieldLocation = scanner.location
            fields.append((try field(&scanner), fieldLocation))
            if scanner.consume(",") { continue }
            break
        }
        guard scanner.isAtEnd || scanner.peek() == "\n" else {
            throw MermaidError.syntax("Unexpected '\(scanner.peek()!)' after a quoted field", at: scanner.location)
        }
        scanner.advance()
        guard fields.count == 3 else {
            throw MermaidError.syntax("Expected 3 fields (source,target,value), found \(fields.count)", at: location)
        }
        let valueText = fields[2].text.trimmingWhitespace()
        guard let value = Double(valueText), value.isFinite,
              valueText.allSatisfy({ "+-.0123456789eE".contains($0) }) else {
            throw MermaidError.syntax("Expected a number, found '\(valueText)'", at: fields[2].location)
        }
        guard value >= 0 else {
            throw MermaidError.semantic("Link values must not be negative", at: fields[2].location)
        }
        let sourceName = fields[0].text.trimmingWhitespace(), targetName = fields[1].text.trimmingWhitespace()
        for (name, field) in [(sourceName, fields[0]), (targetName, fields[1])] where name.isEmpty {
            throw MermaidError.syntax("Expected a node name", at: field.location)
        }
        let link = SankeyDiagram.Link(source: diagram.node(named: sourceName), target: diagram.node(named: targetName),
                                      value: value, location: location)
        diagram.links.append(link)
    }

    /// One field: `"quoted ""text"", with commas"` or plain text up to the
    /// next comma or line end.
    private static func field(_ scanner: inout Scanner) throws -> String {
        let start = scanner.location
        let leading = scanner.read { $0 == " " || $0 == "\t" }
        guard scanner.peek() == "\"" else {
            return leading + scanner.read { $0 != "," && $0 != "\n" && $0 != "\r" }
        }
        scanner.advance()
        var text = ""
        while true {
            guard let c = scanner.advance() else { throw MermaidError.syntax("Unterminated quoted field", at: start) }
            if c == "\"" {
                if scanner.peek() == "\"" { scanner.advance(); text.append("\"") } else { break }
            } else {
                text.append(c)
            }
        }
        scanner.skipWhitespace()
        return text
    }

    /// d3-sankey cannot lay out cycles; report the link that closes one.
    private static func rejectCycles(_ diagram: SankeyDiagram) throws {
        var outgoing = [[Int]](repeating: [], count: diagram.nodes.count)
        for (i, link) in diagram.links.enumerated() { outgoing[link.source].append(i) }
        // 0 = unvisited, 1 = on the current path, 2 = done.
        var state = [Int](repeating: 0, count: diagram.nodes.count)
        for start in diagram.nodes.indices where state[start] == 0 {
            var stack: [(node: Int, next: Int)] = [(start, 0)]
            state[start] = 1
            while let top = stack.last {
                if top.next < outgoing[top.node].count {
                    stack[stack.count - 1].next += 1
                    let link = diagram.links[outgoing[top.node][top.next]]
                    switch state[link.target] {
                    case 1:
                        throw MermaidError.semantic(
                            "Circular link from '\(diagram.nodes[link.source])' to '\(diagram.nodes[link.target])'; sankey links cannot form a cycle",
                            at: link.location)
                    case 0:
                        state[link.target] = 1
                        stack.append((link.target, 0))
                    default: break
                    }
                } else {
                    state[top.node] = 2
                    stack.removeLast()
                }
            }
        }
    }
}
