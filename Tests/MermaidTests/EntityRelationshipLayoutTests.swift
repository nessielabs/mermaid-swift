import Testing
@testable import Mermaid

@Suite("Entity relationship layout")
struct EntityRelationshipLayoutTests {
    let options = RenderOptions(measurer: ApproximateTextMeasurer())

    func render(_ source: String) throws -> Scene { try Mermaid.render(source, options: options) }

    /// Top-level groups with the given role, by id.
    func groups(_ scene: Scene, role: String) -> [String: GroupItem] {
        var result: [String: GroupItem] = [:]
        for case .group(let group) in scene.items where group.role == role { result[group.id ?? ""] = group }
        return result
    }

    func bounds(_ group: GroupItem) -> Rect? {
        Rect.bounding(group.items.flatMap { item -> [Point] in
            guard case .shape(let shape) = item, let b = shape.path.bounds else { return [] }
            return [b.origin, Point(b.maxX, b.maxY)]
        })
    }

    let shop = """
    erDiagram
        CUSTOMER ||--o{ ORDER : places
        CUSTOMER ||--o{ INVOICE : "liable for"
        CUSTOMER }|..|{ DELIVERY-ADDRESS : uses
        ORDER ||--|{ LINE-ITEM : contains
        PRODUCT ||--o{ LINE-ITEM : "ordered in"
        EMPLOYEE |o--o| EMPLOYEE : "reports to"
        CUSTOMER {
            string id PK
            string name "full name"
        }
        LINE-ITEM {
            int quantity
        }
    """

    @Test func registeredAndDetected() throws {
        #expect(Mermaid.detectType("erDiagram\nA") == .entityRelationship)
        #expect(Mermaid.supportedTypes.contains(.entityRelationship))
        #expect(try Mermaid.parse(shop).type == .entityRelationship)
    }

    @Test func entitiesDoNotOverlapAndFitTheCanvas() throws {
        let scene = try render(shop)
        let entities = groups(scene, role: "entity").compactMapValues(bounds)
        #expect(entities.count == 7)
        let frames = Array(entities.values)
        for i in frames.indices {
            for j in (i + 1)..<frames.count { #expect(!frames[i].insetBy(dx: 1, dy: 1).intersects(frames[j])) }
        }
        for frame in frames {
            #expect(frame.minX >= 0 && frame.minY >= 0)
            #expect(frame.maxX <= scene.size.width && frame.maxY <= scene.size.height)
        }
    }

    @Test func relationshipsEndOnTheirEntities() throws {
        let scene = try render(shop)
        let entities = groups(scene, role: "entity").compactMapValues(bounds)
        let relationships = groups(scene, role: "relationship")
        #expect(relationships.count == 6)
        let onSomeEntity = { (p: Point) in
            entities.values.contains { r in
                r.insetBy(dx: -0.5, dy: -0.5).contains(p) && !r.insetBy(dx: 0.5, dy: 0.5).contains(p)
            }
        }
        for (id, group) in relationships {
            // A connector nests its stroke in a group; a self-loop draws its path directly.
            var stroke: ShapeItem?
            switch group.items.first {
            case .group(let line)?: if case .shape(let shape)? = line.items.first { stroke = shape }
            case .shape(let shape)?: stroke = shape
            default: break
            }
            let elements = try #require(stroke?.path.elements, "\(id) has a line")
            guard case .move(let start)? = elements.first, case .line(let end)? = elements.last else {
                Issue.record("\(id) should start with a move and end with a straight run")
                continue
            }
            #expect(onSomeEntity(start), "\(id) starts on an entity outline")
            #expect(onSomeEntity(end), "\(id) ends on an entity outline")
        }
    }

    @Test func nonIdentifyingLinesAreDashed() throws {
        let scene = try render("erDiagram\nA ||..o{ B : x\nC ||--o{ D : y")
        func dashes(_ id: String) -> [Double]? {
            guard let group = groups(scene, role: "relationship")[id], case .group(let line)? = group.items.first,
                  case .shape(let shape)? = line.items.first else { return nil }
            return shape.stroke?.dash
        }
        #expect(dashes("rel-A-B-0") == [8, 8])
        #expect(dashes("rel-C-D-1") == [])
    }

    @Test func tableColumnsAlignAcrossRows() throws {
        let scene = try render("""
        erDiagram
            T {
                string a PK "short"
                varchar(255) longerName FK "a much longer comment"
            }
        """)
        let entity = try #require(groups(scene, role: "entity")["entity-T"])
        var columns: [Double: Int] = [:]
        for case .text(let text) in entity.items where text.alignment == .leading {
            columns[(text.frame.minX * 10).rounded() / 10, default: 0] += 1
        }
        // Four columns, each holding one cell from both rows.
        #expect(columns.count == 4 && columns.values.allSatisfy { $0 == 2 })
    }

    @Test func omittedColumnsAndAttributeFreeEntities() throws {
        let box = EntityRelationshipSceneBuilder(diagram: .init(), context: RenderContext(measurer: ApproximateTextMeasurer()))
        var plain = EntityRelationshipDiagram.Entity(name: "X")
        let empty = box.entityBox(plain, style: ElementStyle())
        #expect(empty.size.width >= 100 && empty.size.height >= 75)
        plain.attributes = [.init(type: "int", name: "id")]
        let table = box.entityBox(plain, style: ElementStyle())
        #expect(table.columnWidths[2] == 0 && table.columnWidths[3] == 0)
        #expect(table.rowHeights.count == 1)
    }

    @Test func crowsFeetReachMatchesDrawing() {
        for foot in CrowsFoot.allCases {
            let items = foot.items(tip: .zero, direction: Point(0, 1), color: .black, background: .white)
            let extent = items.compactMap { item -> Rect? in
                guard case .shape(let shape) = item else { return nil }
                return shape.path.bounds
            }.reduce(Rect(x: 0, y: 0, width: 0, height: 0)) { $0.union($1) }
            #expect(abs(-extent.minY - foot.reach) < 0.01, "\(foot)")
            #expect(extent.maxY <= 0.01, "\(foot) stays outside the entity")
        }
    }

    @Test func directionAndSubgraphsLayOut() throws {
        let lr = try render("erDiagram\ndirection LR\nA ||--o{ B : x")
        let entities = groups(lr, role: "entity").compactMapValues(bounds)
        #expect(try #require(entities["entity-A"]).maxX < (try #require(entities["entity-B"])).minX)
        let grouped = try render("erDiagram\nsubgraph S [Group]\nA ||--o{ B : x\nend\nC ||--|| S : y")
        let cluster = try #require(groups(grouped, role: "cluster")["S"].flatMap(bounds))
        let inner = groups(grouped, role: "entity").compactMapValues(bounds)
        #expect(cluster.contains(try #require(inner["entity-A"]).center))
        #expect(!cluster.contains(try #require(inner["entity-C"]).center))
    }

    @Test func malformedInputNeverCrashes() {
        let inputs = [
            "erDiagram\n{", "erDiagram\nA {", "erDiagram\nA ||", "erDiagram\nA ||--", "erDiagram\n\"",
            "erDiagram\nA[", "erDiagram\nA:::", "erDiagram\nend", "erDiagram\nsubgraph", "erDiagram\nA }|..|{",
            "erDiagram\nA {\n ` \n}", "erDiagram\nA ||--o{ A : self\nA ||--o{ A : again", "erDiagram\nstyle",
            "erDiagram\nclassDef", "erDiagram\nA u--u B : x", "erDiagram\n:::", "erDiagram\nA ||--o{ B :",
        ]
        for input in inputs {
            do { _ = try render(input) } catch is MermaidError {} catch { Issue.record("\(input): \(error)") }
        }
    }
}
