import Testing
@testable import Mermaid

@Suite("Class diagram layout")
struct ClassLayoutTests {
    func render(_ body: String, config: String = "") throws -> Scene {
        try Mermaid.render(config + "classDiagram\n" + body, options: RenderOptions(measurer: ApproximateTextMeasurer()))
    }

    /// Every group in the scene, depth first.
    func groups(_ items: [SceneItem]) -> [GroupItem] {
        items.flatMap { item -> [GroupItem] in
            guard case .group(let group) = item else { return [] }
            return [group] + groups(group.items)
        }
    }

    func group(_ scene: Scene, _ id: String, role: String? = nil) throws -> GroupItem {
        try #require(groups(scene.items).first { $0.id == id && (role == nil || $0.role == role) }, "\(id)")
    }

    /// The first shape of a node group: its outline.
    func frame(_ scene: Scene, _ id: String, role: String? = nil) throws -> Rect {
        let node = try group(scene, id, role: role)
        guard case .shape(let shape) = node.items.first, let bounds = shape.path.bounds else {
            throw MermaidError(.semantic, "no outline for \(id)")
        }
        return bounds
    }

    func texts(_ items: [SceneItem]) -> [TextItem] {
        items.flatMap { item -> [TextItem] in
            switch item {
            case .text(let text): return [text]
            case .group(let group): return texts(group.items)
            case .shape: return []
            }
        }
    }

    func shapes(_ items: [SceneItem]) -> [ShapeItem] {
        items.compactMap { if case .shape(let shape) = $0 { return shape } else { return nil } }
    }

    static let sample = """
    class Animal {
        <<abstract>>
        +int age
        +String gender
        +isMammal() bool
        +mate()$
    }
    class Duck { +String beakColor\n+swim() }
    class Fish { -int sizeInFeet\n-canEat()* }
    Animal <|-- Duck
    Animal <|-- Fish
    Animal "1" o-- "0..*" Egg : lays
    note for Duck "can fly"
    """

    @Test func nodesNeverOverlap() throws {
        let scene = try render(Self.sample)
        let ids = ["Animal", "Duck", "Fish", "Egg", "note0"]
        let frames = try ids.map { try frame(scene, $0) }
        for i in frames.indices {
            for j in frames.indices where j > i {
                #expect(!frames[i].intersects(frames[j]), "\(ids[i]) overlaps \(ids[j])")
            }
        }
    }

    @Test func textStaysInsideItsBox() throws {
        let scene = try render(Self.sample)
        for id in ["Animal", "Duck", "Fish", "Egg"] {
            let box = try frame(scene, id)
            for text in texts(try group(scene, id).items) {
                #expect(box.insetBy(dx: -0.5, dy: -0.5).contains(text.frame.origin), "\(id)")
                #expect(text.frame.maxX <= box.maxX + 0.5 && text.frame.maxY <= box.maxY + 0.5, "\(id)")
            }
        }
    }

    @Test func compartmentsAreOrderedAndAligned() throws {
        let scene = try render(Self.sample)
        let animal = try group(scene, "Animal")
        let lines = texts(animal.items)
        #expect(lines.map(\.block.lines.first!.runs.first!.text)
            == ["«abstract»", "Animal", "+int age", "+String gender", "+isMammal() : bool", "+mate()"])
        #expect(lines[1].block.lines[0].runs[0].font.bold)
        // Members are left aligned at the same inset; headers are centered.
        let box = try frame(scene, "Animal")
        let members = lines.dropFirst(2)
        #expect(Set(members.map(\.frame.minX)).count == 1)
        #expect(members.allSatisfy { $0.alignment == .leading })
        #expect(abs(lines[1].frame.midX - box.midX) < 0.5)
        // Two full-width dividers separate the three compartments.
        let dividers = shapes(animal.items).dropFirst().filter { $0.path.bounds?.height == 0 && $0.path.bounds?.width == box.width }
        #expect(dividers.count == 2)
        let ys = dividers.compactMap(\.path.bounds?.minY)
        #expect(ys[0] > lines[1].frame.maxY && ys[0] < lines[2].frame.minY)
        #expect(ys[1] > lines[3].frame.maxY && ys[1] < lines[4].frame.minY)
    }

    @Test func classifiersStyleMembers() throws {
        let scene = try render(Self.sample)
        let animal = try group(scene, "Animal")
        let mate = try #require(texts(animal.items).first { $0.block.lines[0].runs[0].text == "+mate()" })
        let underline = shapes(animal.items).first {
            guard let b = $0.path.bounds else { return false }
            return b.height == 0 && b.minX == mate.frame.minX && b.minY > mate.frame.midY && b.minY < mate.frame.maxY + 4
        }
        #expect(underline != nil)
        let canEat = try #require(texts(try group(scene, "Fish").items).first { $0.block.lines[0].runs[0].text == "-canEat()" })
        #expect(canEat.block.lines[0].runs[0].font.italic)
    }

    @Test func emptyMembersBoxCanBeHidden() throws {
        let shown = try render("class Duck")
        let hidden = try render("class Duck\nclass Full { x }", config: "---\nconfig:\n  class:\n    hideEmptyMembersBox: true\n---\n")
        #expect(try frame(hidden, "Duck").height < frame(shown, "Duck").height)
        #expect(shapes(try group(hidden, "Duck").items).count == 1)
        #expect(shapes(try group(hidden, "Full").items).count == 3)
    }

    @Test func inheritanceTriangleSitsAtTheParent() throws {
        let scene = try render("Animal <|-- Duck\nCar --|> Vehicle")
        for (edge, parent) in [("id_Animal_Duck_1", "Animal"), ("id_Car_Vehicle_2", "Vehicle")] {
            let items = try group(scene, edge, role: "edge").items
            let triangle = try #require(shapes(items).first { $0.fill != nil && $0.path.flattened().count == 3 })
            let bounds = try #require(triangle.path.bounds)
            let parentFrame = try frame(scene, parent)
            let tip = try #require(triangle.path.flattened().first)
            #expect(parentFrame.insetBy(dx: -1, dy: -1).contains(tip), "\(edge)")
            #expect(!parentFrame.insetBy(dx: 1, dy: 1).intersects(bounds), "\(edge)")
        }
        // In the default top-to-bottom flow the parent is above its child.
        #expect(try frame(scene, "Animal").maxY < frame(scene, "Duck").minY)
    }

    @Test func diamondsSitAtTheWhole() throws {
        let scene = try render("Car *-- Wheel\nPond o-- Duck")
        for (edge, whole) in [("id_Car_Wheel_1", "Car"), ("id_Pond_Duck_2", "Pond")] {
            let items = try group(scene, edge, role: "edge").items
            let diamond = try #require(shapes(items).first { $0.path.flattened().count == 4 })
            let tip = try #require(diamond.path.flattened().first)
            #expect(try frame(scene, whole).insetBy(dx: -1, dy: -1).contains(tip), "\(edge)")
        }
    }

    @Test func cardinalitiesSitNearTheirEnds() throws {
        let scene = try render(Self.sample)
        _ = try group(scene, "id_Animal_Egg_3", role: "edge")
        let all = texts(scene.items)
        let one = try #require(all.first { $0.block.lines.first?.runs.first?.text == "1" })
        let many = try #require(all.first { $0.block.lines.first?.runs.first?.text == "0..*" })
        let animal = try frame(scene, "Animal"), egg = try frame(scene, "Egg")
        func distance(_ r: Rect, _ box: Rect) -> Double { min(abs(r.minY - box.maxY), abs(r.maxY - box.minY)) }
        #expect(distance(one.frame, animal) < distance(one.frame, egg))
        #expect(distance(many.frame, egg) < distance(many.frame, animal))
        let nodes = try ["Animal", "Duck", "Fish", "Egg", "note0"].map { try frame(scene, $0) }
        for label in [one, many] {
            #expect(!nodes.contains { $0.intersects(label.frame) }, "cardinality overlaps a node")
        }
        let relationLabel = try #require(all.first { $0.block.lines.first?.runs.first?.text == "lays" })
        #expect(!relationLabel.frame.intersects(one.frame) && !relationLabel.frame.intersects(many.frame))
    }

    @Test func directionsOrderRelatedClasses() throws {
        let pairs: [(String, (Rect, Rect) -> Bool)] = [
            ("LR", { $0.maxX < $1.minX }), ("RL", { $0.minX > $1.maxX }),
            ("BT", { $0.minY > $1.maxY }), ("TB", { $0.maxY < $1.minY }),
        ]
        for (direction, ordered) in pairs {
            let scene = try render("direction \(direction)\nA --> B")
            #expect(ordered(try frame(scene, "A"), try frame(scene, "B")), "\(direction)")
        }
    }

    @Test func namespacesContainTheirClasses() throws {
        let scene = try render("""
        namespace Platform {
            namespace Auth["Authentication"] {
                class UserService
            }
            class Gateway
        }
        Gateway --> UserService
        Outside --> Gateway
        """)
        let platform = try frame(scene, "Platform", role: "namespace")
        let auth = try frame(scene, "Platform.Auth", role: "namespace")
        #expect(platform.contains(auth.origin) && auth.maxX <= platform.maxX && auth.maxY <= platform.maxY)
        let service = try frame(scene, "UserService", role: "class")
        #expect(auth.contains(service.origin) && service.maxY <= auth.maxY)
        #expect(!platform.intersects(try frame(scene, "Outside", role: "class")))
        #expect(texts(try group(scene, "Platform.Auth", role: "namespace").items).first?.block.lines[0].runs[0].text
            == "Authentication")
    }

    @Test func compactNamespacesDrawOnlyDeclaredOnes() throws {
        let config = "---\nconfig:\n  class:\n    hierarchicalNamespaces: false\n---\n"
        let scene = try render("namespace A.B.C {\nclass X\n}\nnamespace A {\nclass Y\n}", config: config)
        let roles = groups(scene.items).filter { $0.role == "namespace" }.map(\.id)
        #expect(Set(roles.compactMap { $0 }) == ["A.B.C", "A"])
        let title = texts(try group(scene, "A.B.C", role: "namespace").items).first?.block.lines[0].runs[0].text
        #expect(title == "A.B.C")
        #expect(!(try frame(scene, "A", role: "namespace")).intersects(try frame(scene, "A.B.C", role: "namespace")))
    }

    @Test func lollipopsDrawCirclesBesideTheirClass() throws {
        let scene = try render("class Class01\nClass01 --() bar\nfoo ()-- Class01")
        for id in ["interface0", "interface1"] {
            let lollipop = try group(scene, id, role: "interface")
            let circle = try #require(shapes(lollipop.items).first?.path.bounds)
            #expect(abs(circle.width - ClassSceneBuilder.lollipopDiameter) < 0.5)
            #expect(!circle.intersects(try frame(scene, "Class01")))
        }
        let names = texts(scene.items).map { $0.block.lines[0].runs[0].text }
        #expect(names.contains("bar") && names.contains("foo"))
    }

    @Test func stylesAndThemeColors() throws {
        let scene = try render("""
        class A
        class B:::hot
        class C
        style C fill:#00ff00,stroke:#0000ff
        classDef hot fill:#ff0000
        """)
        func paint(_ id: String) throws -> ShapeItem { try #require(shapes(try group(scene, id).items).first) }
        #expect(try paint("A").fill == Theme.default.mainBkg && paint("A").stroke?.color == Theme.default.nodeBorder)
        #expect(try paint("B").fill == Color(css: "#ff0000"))
        #expect(try paint("C").fill == Color(css: "#00ff00") && paint("C").stroke?.color == Color(css: "#0000ff"))
    }

    @Test func dashedRelationsAndNoteConnectors() throws {
        let scene = try render("A ..> B\nnote for A \"hi\"")
        let dependency = try group(scene, "id_A_B_1", role: "edge")
        #expect(shapes(dependency.items).first?.stroke?.dash.isEmpty == false)
        let note = try group(scene, "edgeNote0", role: "edge")
        #expect(shapes(note.items).count == 1 && shapes(note.items).first?.stroke?.dash.isEmpty == false)
    }
}
