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
}
