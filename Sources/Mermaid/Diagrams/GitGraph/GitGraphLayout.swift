/// Positions branches and commits with mermaid.js's git graph geometry.
///
/// Work happens on two axes: the *main* axis commits advance along (x for
/// LR, y for TB/BT) and the *cross* axis branches are stacked on. Commits
/// are 50 apart on the main axis; branch lanes are 50 apart (90 when
/// commit labels are rotated, plus half the label width when vertical).
/// Bottom-to-top is top-to-bottom mirrored.
struct GitGraphLayout {
    struct Settings {
        var showBranches = true
        var showCommitLabel = true
        var rotateCommitLabel = true
        var parallelCommits = false

        init(_ config: ConfigValue) {
            showBranches = config["showBranches"]?.boolValue ?? showBranches
            showCommitLabel = config["showCommitLabel"]?.boolValue ?? showCommitLabel
            rotateCommitLabel = config["rotateCommitLabel"]?.boolValue ?? rotateCommitLabel
            parallelCommits = config["parallelCommits"]?.boolValue ?? parallelCommits
        }
    }

    /// A route between two commits as corner points, drawn with rounded corners.
    struct Arrow {
        var corners: [Point]
        var radius: Double
        /// Index into the palette.
        var colorIndex: Int
    }

    static let commitStep = 40.0
    static let layoutOffset = 10.0

    let diagram: GitGraphDiagram
    let settings: Settings
    var orientation: GitGraphDiagram.Orientation { diagram.orientation }

    /// Cross-axis position and palette index of each branch.
    private(set) var lanes: [String: (position: Double, index: Int)] = [:]
    /// Main-axis position of each commit, before mirroring.
    private(set) var mainPositions: [String: Double] = [:]
    /// Where branch lines start and end on the main axis.
    private(set) var start = 0.0
    private(set) var end = 0.0
    /// Cross-axis lanes already taken by branch lines and rerouted arrows.
    private var takenLanes: [Double] = []

    /// - Parameter labelWidth: the measured width of a branch name.
    init(diagram: GitGraphDiagram, settings: Settings, labelWidth: (String) -> Double) {
        self.diagram = diagram
        self.settings = settings
        var position = 0.0
        for (index, branch) in diagram.orderedBranches.enumerated() {
            lanes[branch.name] = (position, index)
            position += 50 + (settings.rotateCommitLabel ? 40 : 0)
                + (orientation.isVertical ? labelWidth(branch.name) / 2 : 0)
        }
        start = orientation.isVertical ? 30 : 0
        var pos = start
        var furthest = start
        for commit in diagram.commits {
            if settings.parallelCommits {
                let parents = commit.parents.compactMap { mainPositions[$0] }
                pos = parents.max().map { $0 + Self.commitStep } ?? start
            }
            mainPositions[commit.id] = pos + Self.layoutOffset
            pos += Self.commitStep + Self.layoutOffset
            furthest = max(furthest, pos)
        }
        end = furthest
        if settings.showBranches { takenLanes = lanes.values.map(\.position) }
    }

    /// Screen position for main/cross coordinates.
    func point(main: Double, cross: Double) -> Point {
        switch orientation {
        case .leftToRight: return Point(main, cross)
        case .topToBottom: return Point(cross, main)
        case .bottomToTop: return Point(cross, start + end - main)
        }
    }

    func lane(of commit: GitGraphDiagram.Commit) -> (position: Double, index: Int) {
        lanes[commit.branch] ?? (0, 0)
    }

    func position(of commit: GitGraphDiagram.Commit) -> Point {
        point(main: mainPositions[commit.id] ?? 0, cross: lane(of: commit).position)
    }

    /// Every parent-to-child arrow, routed like mermaid.js's `drawArrow`.
    mutating func arrows() -> [Arrow] {
        var result: [Arrow] = []
        let byID = Dictionary(diagram.commits.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        for commit in diagram.commits {
            for parent in commit.parents {
                guard let source = byID[parent] else { continue }
                result.append(arrow(from: source, to: commit))
            }
        }
        return result
    }

    private mutating func arrow(from a: GitGraphDiagram.Commit, to b: GitGraphDiagram.Commit) -> Arrow {
        let (m1, c1) = (mainPositions[a.id] ?? 0, lane(of: a).position)
        let (m2, c2) = (mainPositions[b.id] ?? 0, lane(of: b).position)
        let fromOtherBranch = b.type == .merge && a.id != b.parents.first
        var color = fromOtherBranch ? lane(of: a).index : lane(of: b).index
        let p1 = (m1, c1), p2 = (m2, c2)
        if needsRerouting(a, b, c1: c1, c2: c2) {
            let laneCross = findLane(min(c1, c2), max(c1, c2))
            if c1 > c2 { color = lane(of: a).index }
            return Arrow(corners: [corner(p1), corner((m1, laneCross)), corner((m2, laneCross)), corner(p2)],
                         radius: 10, colorIndex: color)
        }
        if c1 == c2 { return Arrow(corners: [corner(p1), corner(p2)], radius: 20, colorIndex: color) }
        // A merge's second parent travels along its own lane before turning in;
        // everything else turns onto the child's lane first.
        let bend = fromOtherBranch ? (m2, c1) : (m1, c2)
        return Arrow(corners: [corner(p1), corner(bend), corner(p2)], radius: 20, colorIndex: color)
    }

    private func corner(_ p: (Double, Double)) -> Point { point(main: p.0, cross: p.1) }

    /// An arrow must detour when a commit made between its two ends sits on
    /// the lane it would run along.
    private func needsRerouting(_ a: GitGraphDiagram.Commit, _ b: GitGraphDiagram.Commit, c1: Double, c2: Double) -> Bool {
        let curveBranch = c1 < c2 ? b.branch : a.branch
        return diagram.commits.contains { $0.sequence > a.sequence && $0.sequence < b.sequence && $0.branch == curveBranch }
    }

    /// A free lane between two cross positions, at least 10 away from every
    /// lane already in use, found by mermaid.js's bisecting search.
    private mutating func findLane(_ y1: Double, _ y2: Double, depth: Int = 0) -> Double {
        let candidate = y1 + abs(y1 - y2) / 2
        if depth > 5 { return candidate }
        if takenLanes.allSatisfy({ abs($0 - candidate) >= 10 }) {
            takenLanes.append(candidate)
            return candidate
        }
        return findLane(y1, y2 - abs(y1 - y2) / 5, depth: depth + 1)
    }
}
