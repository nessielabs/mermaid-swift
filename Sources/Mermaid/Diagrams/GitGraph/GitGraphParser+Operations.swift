/// Replays git operations with mermaid.js's rules and error messages.
extension GitGraphParser {
    /// A stable stand-in for mermaid.js's random 7-character commit ids, so
    /// the same source always renders the same labels.
    static func generatedID(_ sequence: Int) -> String {
        var z = UInt64(truncatingIfNeeded: sequence) &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        let hex = String(z, radix: 16)
        return "\(sequence)-" + String(String(repeating: "0", count: max(0, 7 - hex.count)) + hex).prefix(7)
    }

    var nextSequence: Int { diagram.commits.count }

    mutating func append(_ commit: GitGraphDiagram.Commit) {
        commitIndex[commit.id] = diagram.commits.count
        diagram.commits.append(commit)
        heads[currentBranch] = .some(commit.id)
        head = commit.id
    }

    mutating func commit(_ s: inout Scanner, at location: SourceLocation) throws {
        let o = try options(&s, allowed: ["id", "msg", "tag", "type"], statement: "commit")
        let sequence = nextSequence
        // mermaid.js only warns about a reused id; the newer commit wins lookups.
        append(.init(id: o.id ?? Self.generatedID(sequence), message: o.message ?? "", sequence: sequence,
                     type: o.type ?? .normal, customType: nil, hasCustomID: o.id != nil, tags: o.tags ?? [],
                     parents: head.map { [$0] } ?? [], branch: currentBranch))
    }

    mutating func branch(_ s: inout Scanner, at location: SourceLocation) throws {
        let name = try name(&s, after: "branch")
        let o = try options(&s, allowed: ["order"], statement: "branch")
        guard heads[name] == nil else {
            throw MermaidError.semantic(
                "Trying to create an existing branch. (Help: Either use a new name if you want create a new branch or try using \"checkout \(name)\")",
                at: location)
        }
        heads[name] = .some(head)
        diagram.branches.append(.init(name: name, order: o.order.map(Double.init)))
        try checkout(name, at: location)
    }

    mutating func checkout(_ name: String, at location: SourceLocation) throws {
        guard let branchHead = heads[name] else {
            throw MermaidError.semantic(
                "Trying to checkout branch which is not yet created. (Help try using \"branch \(name)\")", at: location)
        }
        currentBranch = name
        head = branchHead
    }

    mutating func merge(_ s: inout Scanner, at location: SourceLocation) throws {
        let other = try name(&s, after: "merge")
        let o = try options(&s, allowed: ["id", "tag", "type"], statement: "merge")
        let current = heads[currentBranch].flatMap { $0 }
        let otherHead = heads[other].flatMap { $0 }
        func fail(_ message: String) -> MermaidError { .semantic(message, at: location) }
        if let current, otherHead != nil, commitIndex[current].map({ diagram.commits[$0].branch }) == other {
            throw fail("Cannot merge branch '\(other)' into itself.")
        }
        guard currentBranch != other else { throw fail("Incorrect usage of \"merge\". Cannot merge a branch to itself") }
        guard let current else {
            throw fail("Incorrect usage of \"merge\". Current branch (\(currentBranch))has no commits")
        }
        guard heads[other] != nil else {
            throw fail("Incorrect usage of \"merge\". Branch to be merged (\(other)) does not exist")
        }
        guard let otherHead else {
            throw fail("Incorrect usage of \"merge\". Branch to be merged (\(other)) has no commits")
        }
        guard current != otherHead else { throw fail("Incorrect usage of \"merge\". Both branches have same head") }
        if let id = o.id, commitIndex[id] != nil {
            throw fail("Incorrect usage of \"merge\". Commit with id:\(id) already exists, use different custom id")
        }
        let sequence = nextSequence
        append(.init(id: o.id ?? Self.generatedID(sequence), message: "merged branch \(other) into \(currentBranch)",
                     sequence: sequence, type: .merge, customType: o.type, hasCustomID: o.id != nil,
                     tags: o.tags ?? [], parents: [current, otherHead], branch: currentBranch))
    }

    mutating func cherryPick(_ s: inout Scanner, at location: SourceLocation) throws {
        let o = try options(&s, allowed: ["id", "tag", "parent"], statement: "cherry-pick")
        func fail(_ message: String) -> MermaidError { .semantic(message, at: location) }
        guard let sourceID = o.id, let index = commitIndex[sourceID] else {
            throw fail("Incorrect usage of \"cherryPick\". Source commit id should exist and provided")
        }
        let source = diagram.commits[index]
        if let parent = o.parent, !source.parents.contains(parent) {
            throw fail("Invalid operation: The specified parent commit is not an immediate parent of the cherry-picked commit.")
        }
        if source.type == .merge, o.parent == nil {
            throw fail("Incorrect usage of cherry-pick: If the source commit is a merge commit, an immediate parent commit must be specified.")
        }
        guard source.branch != currentBranch else {
            throw fail("Incorrect usage of \"cherryPick\". Source commit is already on current branch")
        }
        guard let current = heads[currentBranch].flatMap({ $0 }) else {
            throw fail("Incorrect usage of \"cherry-pick\". Current branch (\(currentBranch))has no commits")
        }
        let defaultTag = "cherry-pick:\(source.id)" + (source.type == .merge ? "|parent:\(o.parent ?? "")" : "")
        let sequence = nextSequence
        append(.init(id: Self.generatedID(sequence), message: "cherry-picked \(source.message) into \(currentBranch)",
                     sequence: sequence, type: .cherryPick, customType: nil, hasCustomID: false,
                     tags: o.tags.map { $0.filter { !$0.isEmpty } } ?? [defaultTag],
                     parents: [current, source.id], branch: currentBranch))
    }
}
