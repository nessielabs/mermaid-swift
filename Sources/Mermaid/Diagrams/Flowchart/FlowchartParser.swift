/// Parses flowchart source into a `FlowchartDiagram`.
struct FlowchartParser {
    var scanner: Scanner
    var diagram = FlowchartDiagram()
    var nodeIndex: [String: Int] = [:]
    /// Nodes whose shape or label was set explicitly, as opposed to being
    /// created by a bare reference.
    var definedNodes: Set<String> = []

    struct OpenSubgraph {
        var index: Int
        var references: [String] = []
    }
    var openSubgraphs: [OpenSubgraph] = []
    /// Nodes already claimed by a completed subgraph.
    var claimed: Set<String> = []

    init(_ source: DiagramSource) throws {
        scanner = Scanner(source.text)
        diagram.accessibility = source.accessibility
        let args = source.headerArguments.replacingOccurrences(of: ";", with: "").trimmingWhitespace()
        if !args.isEmpty {
            guard let direction = LayeredGraph.Direction(keyword: args) else {
                throw MermaidError.syntax("Unknown direction '\(args)'", at: source.header.location)
            }
            diagram.direction = direction
        }
    }

    static func parse(_ source: DiagramSource) throws -> FlowchartDiagram {
        var parser = try FlowchartParser(source)
        return try parser.run()
    }

    mutating func run() throws -> FlowchartDiagram {
        while true {
            skipSeparators()
            if scanner.isAtEnd { break }
            try statement()
            scanner.skipWhitespace()
            if !scanner.isAtEnd, !scanner.consume(";"), scanner.peek() != "\n" {
                throw MermaidError.syntax("Unexpected '\(scanner.peek()!)'", at: scanner.location)
            }
        }
        if let open = openSubgraphs.last {
            throw MermaidError.syntax("Subgraph '\(diagram.subgraphs[open.index].id)' is missing 'end'", at: scanner.location)
        }
        finalize()
        return diagram
    }

    mutating func skipSeparators() {
        while let c = scanner.peek(), c == " " || c == "\t" || c == "\r" || c == "\n" || c == ";" { scanner.advance() }
    }

    mutating func statement() throws {
        if scanner.consumeKeyword("subgraph", caseInsensitive: false) {
            openSubgraph(restOfStatement())
        } else if scanner.consumeKeyword("end", caseInsensitive: false) {
            try closeSubgraph()
        } else if scanner.consumeKeyword("direction", caseInsensitive: false) {
            let location = scanner.location
            let word = restOfStatement()
            guard let direction = LayeredGraph.Direction(keyword: word) else {
                throw MermaidError.syntax("Unknown direction '\(word)'", at: location)
            }
            if let open = openSubgraphs.last { diagram.subgraphs[open.index].direction = direction } else { diagram.direction = direction }
        } else if scanner.consumeKeyword("classDef", caseInsensitive: false) {
            let (names, css) = splitFirstWord(restOfStatement())
            for name in names.split(separator: ",") {
                let key = name.trimmingWhitespace()
                diagram.classDefinitions[key] = (diagram.classDefinitions[key] ?? ElementStyle()).overlaid(with: ElementStyle(css: css))
            }
        } else if scanner.consumeKeyword("class", caseInsensitive: false) {
            let (ids, classes) = splitFirstWord(restOfStatement())
            for id in ids.split(separator: ",").map({ $0.trimmingWhitespace() }) {
                applyClasses(classes.split(separator: ",").map { $0.trimmingWhitespace() }, to: id)
            }
        } else if scanner.consumeKeyword("style", caseInsensitive: false) {
            let (id, css) = splitFirstWord(restOfStatement())
            if let i = diagram.subgraphs.firstIndex(where: { $0.id == id }) {
                diagram.subgraphs[i].style = diagram.subgraphs[i].style.overlaid(with: ElementStyle(css: css))
            } else {
                let i = ensureNode(id, reference: false)
                diagram.nodes[i].style = diagram.nodes[i].style.overlaid(with: ElementStyle(css: css))
            }
        } else if scanner.consumeKeyword("linkStyle", caseInsensitive: false) {
            try linkStyle()
        } else if scanner.consumeKeyword("click", caseInsensitive: false) {
            click(restOfStatement())
        } else {
            try chain()
        }
    }

    /// The rest of the line, without a trailing `;`.
    mutating func restOfStatement() -> String {
        var text = scanner.read { $0 != "\n" }.trimmingWhitespace()
        while text.hasSuffix(";") { text.removeLast() }
        return text.trimmingWhitespace()
    }

    func splitFirstWord(_ text: String) -> (String, String) {
        let word = String(text.prefix { !$0.isWhitespace })
        return (word, String(text.dropFirst(word.count)).trimmingWhitespace())
    }

    mutating func applyClasses(_ classes: [String], to id: String) {
        if let i = diagram.subgraphs.firstIndex(where: { $0.id == id }) {
            diagram.subgraphs[i].classes += classes
        } else {
            let i = ensureNode(id, reference: false)
            diagram.nodes[i].classes += classes
        }
    }

    mutating func linkStyle() throws {
        let location = scanner.location
        var (targets, rest) = splitFirstWord(restOfStatement())
        var curve: Curve?
        if rest.hasPrefix("interpolate ") {
            let (_, afterKeyword) = splitFirstWord(rest)
            let (name, css) = splitFirstWord(afterKeyword)
            curve = Curve(name: name)
            rest = css
        }
        let style = ElementStyle(css: rest)
        if targets == "default" {
            diagram.defaultLinkStyle = diagram.defaultLinkStyle.overlaid(with: style)
            if let curve { diagram.defaultLinkCurve = curve }
            return
        }
        for part in targets.split(separator: ",") {
            guard let index = Int(part.trimmingWhitespace()) else {
                throw MermaidError.syntax("linkStyle expects link numbers or 'default'", at: location)
            }
            diagram.linkStyles[index] = (diagram.linkStyles[index] ?? ElementStyle()).overlaid(with: style)
            if let curve { diagram.linkCurves[index] = curve }
        }
    }

    /// `click id callback|href|call ... "url" "tooltip" target`
    mutating func click(_ text: String) {
        let (id, rest) = splitFirstWord(text)
        let quoted = rest.split(separator: "\"", omittingEmptySubsequences: false).enumerated()
            .filter { $0.offset % 2 == 1 }.map { String($0.element) }
        let i = ensureNode(id, reference: false)
        if rest.hasPrefix("href") || rest.hasPrefix("\"") {
            diagram.nodes[i].link = quoted.first
            diagram.nodes[i].tooltip = quoted.count > 1 ? quoted[1] : nil
        } else {
            diagram.nodes[i].tooltip = quoted.last
        }
    }

    // MARK: - Subgraphs

    mutating func openSubgraph(_ header: String) {
        var id = header, title = header
        if let open = header.firstIndex(of: "["), header.hasSuffix("]") {
            id = String(header[..<open]).trimmingWhitespace()
            title = String(header[header.index(after: open)..<header.index(before: header.endIndex)])
        }
        title = Self.unquote(title.trimmingWhitespace())
        if id.hasPrefix("\"") { id = Self.unquote(id) }
        if id.isEmpty { id = "subGraph\(diagram.subgraphs.count)" }
        let parent = openSubgraphs.last.map { diagram.subgraphs[$0.index].id }
        diagram.subgraphs.append(.init(id: id, title: title, parent: parent))
        openSubgraphs.append(OpenSubgraph(index: diagram.subgraphs.count - 1))
    }

    mutating func closeSubgraph() throws {
        guard let open = openSubgraphs.popLast() else {
            throw MermaidError.syntax("'end' without a matching 'subgraph'", at: scanner.location)
        }
        var members: [String] = []
        for id in open.references where !claimed.contains(id) && !members.contains(id) {
            if let child = diagram.subgraphs.firstIndex(where: { $0.id == id }) {
                if diagram.subgraphs[child].parent == nil, child != open.index {
                    diagram.subgraphs[child].parent = diagram.subgraphs[open.index].id
                }
                continue
            }
            members.append(id)
        }
        claimed.formUnion(members)
        diagram.subgraphs[open.index].nodes = members
        // Outer subgraphs also see everything referenced inside this one.
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].references += open.references }
    }

    static func unquote(_ text: String) -> String { text.unquoted }

    /// Drops placeholder nodes that are really references to subgraphs.
    mutating func finalize() {
        let subgraphIDs = Set(diagram.subgraphs.map(\.id))
        diagram.nodes.removeAll { subgraphIDs.contains($0.id) && !definedNodes.contains($0.id) }
        for i in diagram.subgraphs.indices {
            diagram.subgraphs[i].nodes.removeAll { subgraphIDs.contains($0) && !definedNodes.contains($0) }
        }
    }

    // MARK: - Node chains

    /// `A[Label] --> B & C -- text --> D`
    mutating func chain() throws {
        var previous = try nodeGroup()
        while true {
            var probe = scanner
            probe.skipWhitespace()
            guard let link = try FlowchartLinkScanner.scan(&probe) else { break }
            scanner = probe
            scanner.skipWhitespace()
            let next = try nodeGroup()
            for from in previous {
                for to in next {
                    var edge = FlowchartDiagram.Link(from: from, to: to, label: link.label, stroke: link.stroke,
                                                     startMarker: link.startMarker, endMarker: link.endMarker,
                                                     length: link.length)
                    edge.id = link.id
                    diagram.links.append(edge)
                }
            }
            previous = next
        }
    }

    /// One or more nodes joined by `&`.
    mutating func nodeGroup() throws -> [String] {
        var ids = [try node()]
        while true {
            var probe = scanner
            probe.skipWhitespace()
            guard probe.consume("&") else { break }
            probe.skipWhitespace()
            scanner = probe
            ids.append(try node())
        }
        return ids
    }

    mutating func node() throws -> String {
        let location = scanner.location
        guard let token = try FlowchartNodeScanner.scan(&scanner) else {
            let found = scanner.peek().map { "'\($0)'" } ?? "end of input"
            throw MermaidError.syntax("Expected a node but found \(found)", at: location)
        }
        // `e1@{ animate: true }` configures a link, not a node.
        if token.hasMetadata, token.shape == nil, token.label == nil,
           diagram.links.contains(where: { $0.id == token.id }) {
            return token.id
        }
        let i = ensureNode(token.id)
        if let label = token.label { diagram.nodes[i].label = label }
        if let shape = token.shape { diagram.nodes[i].shape = shape }
        if token.label != nil || token.shape != nil { definedNodes.insert(token.id) }
        diagram.nodes[i].classes += token.classes
        return token.id
    }

    /// The index of the node with `id`, creating it on first reference and
    /// recording the reference for subgraph membership.
    @discardableResult
    mutating func ensureNode(_ id: String, reference: Bool = true) -> Int {
        if reference, !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].references.append(id) }
        if let i = nodeIndex[id] { return i }
        diagram.nodes.append(.init(id: id))
        nodeIndex[id] = diagram.nodes.count - 1
        return diagram.nodes.count - 1
    }
}
