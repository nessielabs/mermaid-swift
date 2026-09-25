/// A parsed git graph (`gitGraph`): commits on branches, with merges and
/// cherry-picks, replayed from the statements in order.
public struct GitGraphDiagram: Sendable {
    public static let type = DiagramType.gitGraph

    /// The direction commits advance in.
    public enum Orientation: String, Hashable, Sendable {
        case leftToRight = "LR", topToBottom = "TB", bottomToTop = "BT"

        var isVertical: Bool { self != .leftToRight }
    }

    public enum CommitType: String, Hashable, Sendable {
        case normal = "NORMAL", reverse = "REVERSE", highlight = "HIGHLIGHT", merge = "MERGE", cherryPick = "CHERRY_PICK"
    }

    public struct Commit: Hashable, Sendable {
        public var id: String
        public var message: String
        /// Creation order, starting at 0.
        public var sequence: Int
        public var type: CommitType
        /// A merge's `type:` override, which changes only how it is drawn.
        public var customType: CommitType?
        /// Whether the id was given explicitly (merge labels show only then).
        public var hasCustomID: Bool
        public var tags: [String]
        /// Parent ids; a merge's second parent is the merged branch's head,
        /// a cherry-pick's is the picked commit.
        public var parents: [String]
        public var branch: String

        /// The shape the commit is drawn with.
        public var symbol: CommitType { customType ?? type }
    }

    public struct Branch: Hashable, Sendable {
        public var name: String
        /// The `order:` given at creation (or `mainBranchOrder`), if any.
        public var order: Double?
    }

    public var orientation: Orientation = .leftToRight
    /// Commits in creation order.
    public var commits: [Commit] = []
    /// Branches in creation order; the main branch is first.
    public var branches: [Branch] = []
    public var title: String?
    public var accessibility = Accessibility()

    public init() {}

    public func commit(_ id: String) -> Commit? { commits.first { $0.id == id } }

    /// Branches in display order, as mermaid.js sorts them: by explicit
    /// `order`, with branches that have none placed in creation order
    /// between order 0 and 1.
    public var orderedBranches: [Branch] {
        let count = Double(branches.count + 1)
        let keyed: [(branch: Branch, key: Double, index: Int)] = branches.enumerated().map { index, branch in
            (branch, branch.order ?? Double(index) / count, index)
        }
        return keyed.sorted { $0.key != $1.key ? $0.key < $1.key : $0.index < $1.index }.map(\.branch)
    }
}
