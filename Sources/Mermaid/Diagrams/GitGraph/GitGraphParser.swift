/// Parses git graph source and replays it into a `GitGraphDiagram`.
///
/// Statements follow mermaid.js's Langium grammar: `commit`, `branch`,
/// `checkout`/`switch`, `merge`, `cherry-pick`, and `title`, one per line.
/// Replaying them enforces the same rules mermaid.js does (no merging a
/// branch into itself, no checking out a missing branch, ...), reported as
/// located errors.
struct GitGraphParser {
    var diagram = GitGraphDiagram()
    var mainBranch: String
    var currentBranch: String
    /// Head commit id of each branch; nil until the branch has a commit.
    var heads: [String: String?] = [:]
    var commitIndex: [String: Int] = [:]
    var head: String?

    init(_ source: DiagramSource) throws {
        let config = source.config["gitGraph"] ?? .object([:])
        mainBranch = config["mainBranchName"]?.stringValue ?? "main"
        currentBranch = mainBranch
        heads[mainBranch] = .some(nil)
        diagram.branches = [.init(name: mainBranch, order: config["mainBranchOrder"]?.numberValue ?? 0)]
        diagram.accessibility = source.accessibility
        diagram.orientation = try Self.orientation(source)
    }

    static func parse(_ source: DiagramSource) throws -> GitGraphDiagram {
        var parser = try GitGraphParser(source)
        for line in joiningOpenStrings(source.lines) { try parser.statement(line) }
        return parser.diagram
    }

    /// Langium strings may contain newlines (`branch "Feature A` on one line,
    /// `(ongoing)"` on the next), so a line with an unclosed double quote is
    /// joined with the lines that follow until the quote closes.
    static func joiningOpenStrings(_ lines: [SourceLine]) -> [SourceLine] {
        var result: [SourceLine] = []
        var pending: SourceLine?
        func isOpen(_ text: String) -> Bool {
            var open = false, escaped = false
            for c in text {
                if escaped { escaped = false } else if c == "\\" { escaped = true } else if c == "\"" { open.toggle() }
            }
            return open
        }
        for line in lines {
            if var joined = pending {
                joined.text += "\n" + line.text
                pending = isOpen(joined.text) ? joined : nil
                if pending == nil { result.append(joined) }
            } else if isOpen(line.text) {
                pending = line
            } else {
                result.append(line)
            }
        }
        if let pending { result.append(pending) }
        return result
    }

    /// `gitGraph`, `gitGraph:`, or `gitGraph LR:` / `TB:` / `BT:`. The colon
    /// after a direction is optional here, a leniency beyond mermaid.js.
    static func orientation(_ source: DiagramSource) throws -> GitGraphDiagram.Orientation {
        var text = source.header.text.dropFirst("gitGraph".count).trimmingWhitespace()
        if text.hasSuffix(":") { text.removeLast() }
        text = text.trimmingWhitespace()
        if text.isEmpty { return .leftToRight }
        guard let orientation = GitGraphDiagram.Orientation(rawValue: text) else {
            throw MermaidError.syntax("Unknown git graph orientation '\(text)'; use LR, TB or BT",
                                      at: source.header.location(atOffset: "gitGraph".count + 1))
        }
        return orientation
    }

    // MARK: - Statements

    mutating func statement(_ line: SourceLine) throws {
        let text = line.textWithoutComment
        if let title = PacketParser.titleStatement(text) {
            diagram.title = title
            return
        }
        var s = Scanner(text, at: line.location)
        let keyword = s.read { $0.isWordCharacter || $0 == "-" }
        s.skipWhitespace()
        switch keyword {
        case "commit": try commit(&s, at: line.location)
        case "branch": try branch(&s, at: line.location)
        case "checkout", "switch": try checkout(try name(&s, after: keyword), at: line.location)
        case "merge": try merge(&s, at: line.location)
        case "cherry-pick": try cherryPick(&s, at: line.location)
        default:
            throw MermaidError.syntax(
                "Expected 'commit', 'branch', 'checkout', 'switch', 'merge' or 'cherry-pick' but found '\(keyword.isEmpty ? text : keyword)'",
                at: line.location)
        }
        s.skipWhitespace()
        if let extra = s.peek() {
            throw MermaidError.syntax("Unexpected '\(extra)' in '\(keyword)' statement", at: s.location)
        }
    }

    /// A branch name: a quoted string or a reference such as `feature/login-2.0`.
    func name(_ s: inout Scanner, after keyword: String) throws -> String {
        if let quoted = try s.readQuoted(multiline: true) { return quoted }
        let location = s.location
        var name = s.read { $0.isWordCharacter || $0 == "-" || $0 == "." || $0 == "/" }
        // A reference cannot end with '.' or '/', as in the Langium REFERENCE terminal.
        while let last = name.last, last == "." || last == "/" { name.removeLast() }
        guard !name.isEmpty, name.first?.isWordCharacter == true else {
            throw MermaidError.syntax("Expected a branch name after '\(keyword)'", at: location)
        }
        return name
    }

    /// Options written as `key: value`, in any order. Values are quoted
    /// strings, commit types, or integers depending on the key.
    struct Options {
        var id: String?
        var message: String?
        var tags: [String]?
        var type: GitGraphDiagram.CommitType?
        var parent: String?
        var order: Int?
    }

    func options(_ s: inout Scanner, allowed: Set<String>, statement: String) throws -> Options {
        var result = Options()
        while true {
            s.skipWhitespace()
            guard !s.isAtEnd else { return result }
            let location = s.location
            if allowed.contains("msg"), let bare = try s.readQuoted(multiline: true) {
                result.message = bare
                continue
            }
            let key = s.read { $0.isLetter }
            s.skipWhitespace()
            guard !key.isEmpty, allowed.contains(key), s.consume(":") else {
                let expected = allowed.sorted().map { "'\($0):'" }.joined(separator: ", ")
                throw MermaidError.syntax("Unexpected '\(key.isEmpty ? String(s.peek() ?? " ") : key)' in '\(statement)'; expected \(expected)",
                                          at: location)
            }
            s.skipWhitespace()
            let valueLocation = s.location
            switch key {
            case "type":
                let word = s.read { $0.isLetter || $0 == "_" }
                guard let type = GitGraphDiagram.CommitType(rawValue: word.uppercased()),
                      [.normal, .reverse, .highlight].contains(type) else {
                    throw MermaidError.syntax("Commit type must be NORMAL, REVERSE or HIGHLIGHT", at: valueLocation)
                }
                result.type = type
            case "order":
                guard let order = s.readInteger() else { throw MermaidError.syntax("Branch order must be a number", at: valueLocation) }
                result.order = order
            default:
                // Leniency beyond mermaid.js: unquoted values such as `id: abc` are accepted.
                let value = try s.readQuoted(multiline: true) ?? s.read { !$0.isWhitespace }
                switch key {
                case "id": result.id = value
                case "msg": result.message = value
                case "tag": result.tags = (result.tags ?? []) + [value]
                case "parent": result.parent = value
                default: break
                }
            }
        }
    }
}
