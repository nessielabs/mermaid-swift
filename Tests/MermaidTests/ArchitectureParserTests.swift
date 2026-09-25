import Testing
@testable import Mermaid

@Suite("Architecture parsing")
struct ArchitectureParserTests {
    func parse(_ body: String, header: String = "architecture-beta") throws -> ArchitectureDiagram {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try ArchitectureParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    func parseError(_ body: String) -> MermaidError? {
        do { _ = try parse(body); return nil } catch let error as MermaidError { return error } catch { return nil }
    }

    @Test func groupsServicesAndJunctions() throws {
        let d = try parse("""
        title Cloud
        group api(cloud)[API]
        group private(cloud)[Private API] in api
        service db(database)[My Database] in private
        service box "Text icon"[Box]
        service bare[Bare]
        service plain
        junction j in api
        service aws(logos:aws-s3)["Quoted [title]"]
        """)
        #expect(d.title == "Cloud")
        #expect(d.groups.map(\.id) == ["api", "private"] && d.group("private")?.parent == "api")
        #expect(d.group("api")?.icon == "cloud" && d.group("api")?.title == "API")
        let db = try #require(d.node("db"))
        #expect(db.icon == "database" && db.title == "My Database" && db.parent == "private")
        #expect(d.node("box")?.iconText == "Text icon" && d.node("box")?.title == "Box")
        #expect(d.node("bare")?.icon == nil && d.node("bare")?.title == "Bare")
        #expect(d.node("plain")?.title == nil)
        #expect(d.node("j")?.kind == .junction && d.node("j")?.parent == "api")
        #expect(d.node("aws")?.icon == "logos:aws-s3" && d.node("aws")?.title == "Quoted [title]")
        #expect(d.declarationOrder == ["api", "private", "db", "box", "bare", "plain", "j", "aws"])
    }

    @Test func edgesWithSidesArrowsLabelsAndGroups() throws {
        let d = try parse("""
        group g1[One]
        group g2[Two]
        service a[A] in g1
        service b[B] in g2
        service my-svc[C]
        a:L -- R:b
        a:T --> B:b
        a:R <-- L:my-svc
        a:B <--> T:b
        a{group}:R -[Calls]-> L:b{group}
        my-svc:B -[plain label]- T:a
        """)
        #expect(d.edges.count == 6)
        let e0 = d.edges[0]
        #expect(e0.from == "a" && e0.fromSide == .left && e0.to == "b" && e0.toSide == .right)
        #expect(!e0.arrowAtSource && !e0.arrowAtTarget)
        #expect(d.edges[1].arrowAtTarget && !d.edges[1].arrowAtSource)
        #expect(d.edges[2].arrowAtSource && d.edges[2].to == "my-svc")
        #expect(d.edges[3].arrowAtSource && d.edges[3].arrowAtTarget)
        #expect(d.edges[4].fromGroup && d.edges[4].toGroup && d.edges[4].label == "Calls" && d.edges[4].arrowAtTarget)
        #expect(d.edges[5].label == "plain label" && d.edges[5].from == "my-svc")
    }

    @Test func alignments() throws {
        let d = try parse("""
        service a[A]
        service b[B]
        junction c
        align row a b c
        align column a b
        """)
        #expect(d.alignments == [.init(axis: .row, members: ["a", "b", "c"]), .init(axis: .column, members: ["a", "b"])])
    }

    @Test func idsMayStartWithKeywords() throws {
        let d = try parse("""
        service group-a[A]
        service titles[T]
        group-a:R -- L:titles
        """)
        #expect(d.edges.first?.from == "group-a")
    }

    @Test func declarationErrorsAreLocated() {
        #expect(parseError("service a[A] in nowhere")?.location == SourceLocation(line: 2, column: 17))
        #expect(parseError("service a[A]\nservice a[B]")?.location == SourceLocation(line: 3, column: 9))
        #expect(parseError("group g[G] in g")?.message.contains("within itself") == true)
        #expect(parseError("service s[S]\nservice t[T] in s")?.message.contains("not a group") == true)
        #expect(parseError("service a(database[A]")?.location == SourceLocation(line: 2, column: 10))
        #expect(parseError("service a[A")?.location == SourceLocation(line: 2, column: 10))
        #expect(parseError("service a[A] extra")?.location == SourceLocation(line: 2, column: 14))
    }

    @Test func edgeErrorsAreLocated() {
        let base = "group g[G]\nservice a[A] in g\nservice b[B] in g\nservice c[C]\n"
        #expect(parseError(base + "a:X -- L:b")?.location == SourceLocation(line: 6, column: 3))
        #expect(parseError(base + "a:R -> L:b")?.location == SourceLocation(line: 6, column: 5))
        #expect(parseError(base + "a:R -- L:zz")?.location == SourceLocation(line: 6, column: 10))
        #expect(parseError(base + "a:R -- L:g")?.message.contains("group [g]") == true)
        #expect(parseError(base + "a{group}:R -- L:b")?.kind == .semantic)
        #expect(parseError(base + "c{group}:R -- L:a")?.message.contains("not in a group") == true)
        #expect(parseError(base + "a R -- L:b")?.location == SourceLocation(line: 6, column: 2))
    }

    @Test func alignmentErrors() {
        #expect(parseError("service a[A]\nalign row a")?.message.contains("two members") == true)
        #expect(parseError("service a[A]\nalign diagonal a a")?.location == SourceLocation(line: 3, column: 7))
        #expect(parseError("service a[A]\nservice b[B]\nalign row a b a")?.message.contains("more than once") == true)
        #expect(parseError("group g[G]\nservice a[A]\nalign column a g")?.kind == .semantic)
    }
}
