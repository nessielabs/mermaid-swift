import Testing
@testable import Mermaid

@Suite("Git graphs")
struct GitGraphTests {
    func parse(_ source: String) throws -> GitGraphDiagram {
        try #require(try Mermaid.parse(source).diagram as? GitGraphDiagram)
    }

    func error(_ source: String) -> MermaidError? {
        do { _ = try parse(source); return nil } catch let e as MermaidError { return e } catch { return nil }
    }

    @Test func replaysCommitsBranchesAndMerges() throws {
        let d = try parse("""
        gitGraph
          commit id: "A" tag: "v1" tag: "stable"
          commit "a message" type: HIGHLIGHT
          branch develop order: 2
          switch develop
          commit id:"B" msg: "work"
          checkout main
          merge develop id: "M" tag: "release" type: REVERSE
          branch "cherry-pick"
          commit id: "C"
          checkout main
          cherry-pick id: "B" tag: ""
        """)
        #expect(d.commits.map(\.branch) == ["main", "main", "develop", "main", "cherry-pick", "main"])
        #expect(d.commits[0].tags == ["v1", "stable"] && d.commits[0].hasCustomID)
        #expect(d.commits[1].message == "a message" && d.commits[1].type == .highlight)
        #expect(d.commits[1].id == GitGraphParser.generatedID(1) && d.commits[1].id.hasPrefix("1-"))
        #expect(d.commits[2].parents == [d.commits[1].id] && d.commits[2].message == "work")
        let merge = d.commits[3]
        #expect(merge.type == .merge && merge.symbol == .reverse && merge.parents == [d.commits[1].id, "B"])
        #expect(merge.message == "merged branch develop into main")
        let pick = d.commits[5]
        #expect(pick.type == .cherryPick && pick.parents == ["M", "B"] && pick.tags.isEmpty)
        #expect(d.branches.map(\.name) == ["main", "develop", "cherry-pick"])
        #expect(d.orderedBranches.map(\.name) == ["main", "cherry-pick", "develop"])
    }

    @Test func cherryPicksGetADefaultTag() throws {
        let d = try parse("gitGraph\ncommit id: \"A\"\nbranch dev\ncommit id: \"B\"\ncheckout main\ncherry-pick id: \"B\"")
        #expect(d.commits.last?.tags == ["cherry-pick:B"])
    }

    @Test func headerOrientationsAndTitle() throws {
        #expect(try parse("gitGraph\ncommit").orientation == .leftToRight)
        #expect(try parse("gitGraph:\ncommit").orientation == .leftToRight)
        #expect(try parse("gitGraph TB:\ncommit").orientation == .topToBottom)
        #expect(try parse("gitGraph BT:\ncommit").orientation == .bottomToTop)
        #expect(try parse("gitGraph LR\ncommit\ntitle Flow").title == "Flow")
        #expect(error("gitGraph XY:\ncommit")?.location?.line == 1)
    }

    @Test func mainBranchNameAndOrderComeFromConfiguration() throws {
        let d = try parse("""
        ---
        config:
          gitGraph:
            mainBranchName: trunk
            mainBranchOrder: 2
        ---
        gitGraph
          commit
          branch a order: 1
          branch b
          checkout trunk
          commit
        """)
        #expect(d.commits.map(\.branch) == ["trunk", "trunk"])
        #expect(d.orderedBranches.map(\.name) == ["b", "a", "trunk"])
    }

    @Test func multiLineQuotedBranchNames() throws {
        let d = try parse("gitGraph\ncommit\nbranch \"Feature A\n  (ongoing)\"\ncommit")
        #expect(d.branches[1].name == "Feature A\n(ongoing)")
        #expect(d.commits[1].branch == "Feature A\n(ongoing)")
    }

    @Test(arguments: [
        ("gitGraph\ncommit\nmerge main", 3, "Cannot merge branch 'main' into itself."),
        ("gitGraph\nmerge main", 2, "Cannot merge a branch to itself"),
        ("gitGraph\ncommit\nbranch dev\nmerge main", 4, "Cannot merge branch 'main' into itself."),
        ("gitGraph\nbranch dev\ncommit\ncheckout main\nmerge dev", 5, "Current branch (main)has no commits"),
        ("gitGraph\ncommit\nmerge nope", 3, "Branch to be merged (nope) does not exist"),
        ("gitGraph\ncommit\nbranch dev\ncheckout main\nbranch x\nmerge dev", 6, "Both branches have same head"),
        ("gitGraph\ncommit id: \"A\"\nbranch d\ncommit\ncheckout main\nmerge d id: \"A\"", 6, "Commit with id:A already exists"),
        ("gitGraph\ncommit\nbranch main", 3, "Trying to create an existing branch"),
        ("gitGraph\ncheckout nope", 2, "Trying to checkout branch which is not yet created"),
        ("gitGraph\ncommit\ncherry-pick id: \"zz\"", 3, "Source commit id should exist"),
        ("gitGraph\ncommit id: \"A\"\ncommit\ncherry-pick id: \"A\"", 4, "Source commit is already on current branch"),
        ("gitGraph\ncommit id: \"A\"\nbranch d\ncommit id: \"B\"\ncheckout main\nmerge d id: \"M\"\nbranch e\ncommit\ncherry-pick id: \"M\"",
         9, "an immediate parent commit must be specified"),
        ("gitGraph\ncommit id: \"A\"\nbranch d\ncommit id: \"B\"\ncheckout main\nmerge d id: \"M\"\nbranch e\ncommit\ncherry-pick id: \"M\" parent: \"Q\"",
         9, "not an immediate parent"),
        ("gitGraph\ncommit type: WEIRD", 2, "NORMAL, REVERSE or HIGHLIGHT"),
        ("gitGraph\npush origin", 2, "Expected 'commit'"),
        ("gitGraph\ncommit id: \"A\" extra: \"x\"", 2, "Unexpected 'extra'"),
    ] as [(String, Int, String)])
    func mermaidErrorsAreLocated(source: String, line: Int, message: String) {
        let e = error(source)
        #expect(e?.location?.line == line, "\(String(describing: e))")
        #expect(e?.message.contains(message) == true, "\(String(describing: e))")
    }

    func layout(_ source: String) throws -> (GitGraphDiagram, GitGraphLayout) {
        let d = try parse(source)
        let context = RenderContext(measurer: ApproximateTextMeasurer(), config: try Mermaid.parse(source).config)
        return (d, GitGraphSceneBuilder(diagram: d, context: context).layout())
    }

    let flow = """
    gitGraph
      commit id: "1"
      branch dev
      commit id: "2"
      checkout main
      commit id: "3"
      checkout dev
      commit id: "4"
      checkout main
      merge dev id: "5"
    """

    @Test func commitsAdvanceAndBranchesStack() throws {
        let (d, layout) = try layout(flow)
        let points = d.commits.map { layout.position(of: $0) }
        // LR: each commit 50 further right, main above dev, 90 apart with rotated labels.
        #expect(zip(points, points.dropFirst()).allSatisfy { $1.x - $0.x == 50 })
        #expect(points[1].y - points[0].y == 90)
        // No two commits share a position.
        #expect(Set(points.map { "\($0.x),\($0.y)" }).count == points.count)
    }

    @Test func parallelCommitsAlignByDepth() throws {
        let (d, layout) = try layout("---\nconfig:\n  gitGraph:\n    parallelCommits: true\n---\n" + flow)
        let x = Dictionary(uniqueKeysWithValues: d.commits.map { ($0.id, layout.position(of: $0).x) })
        #expect(x["2"] == x["3"] && x["4"]! == x["2"]! + 50 && x["5"]! == x["4"]! + 50)
    }

    @Test func verticalOrientationsSwapAndMirrorAxes() throws {
        let (d, tb) = try layout(flow.replacingOccurrences(of: "gitGraph", with: "gitGraph TB:"))
        let (_, bt) = try layout(flow.replacingOccurrences(of: "gitGraph", with: "gitGraph BT:"))
        let down = d.commits.map { tb.position(of: $0).y }, up = d.commits.map { bt.position(of: $0).y }
        #expect(zip(down, down.dropFirst()).allSatisfy { $0 < $1 })
        #expect(zip(up, up.dropFirst()).allSatisfy { $0 > $1 })
        #expect(tb.position(of: d.commits[1]).x > tb.position(of: d.commits[0]).x)
    }

    @Test func arrowsConnectParentsToChildrenWithOrthogonalBends() throws {
        var (d, layout) = try layout(flow)
        let arrows = layout.arrows()
        #expect(arrows.count == d.commits.reduce(0) { $0 + $1.parents.count })
        for arrow in arrows {
            for (a, b) in zip(arrow.corners, arrow.corners.dropFirst()) { #expect(a.x == b.x || a.y == b.y) }
        }
        // The merge's second parent arrow takes the merged branch's color.
        let devIndex = try #require(layout.lanes["dev"]).index
        #expect(arrows.last?.colorIndex == devIndex)
    }

    @Test func rendersBulletsLabelsTagsAndBranches() throws {
        let source = """
        ---
        config:
          gitGraph:
            showBranches: false
        ---
        gitGraph
          commit id: "one" tag: "v1"
          commit type: HIGHLIGHT
        """
        let svg = try Mermaid.render(source, options: RenderOptions(measurer: ApproximateTextMeasurer())).svg
        #expect(svg.contains(">one</text>") && svg.contains(">v1</text>"))
        #expect(!svg.contains("class=\"branch\""))
        let shown = try Mermaid.render(flow, options: RenderOptions(measurer: ApproximateTextMeasurer())).svg
        #expect(shown.components(separatedBy: "class=\"branch\"").count - 1 == 2)
        #expect(shown.contains(">5</text>")) // merges with a custom id are labelled
    }
}
