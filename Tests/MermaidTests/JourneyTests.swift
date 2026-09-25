import Testing
@testable import Mermaid

@Suite("User journey")
struct JourneyTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func parse(_ body: String) throws -> JourneyDiagram {
        let prepared = try Preprocessor.prepare("journey\n" + body)
        return try JourneyParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    let sample = """
        title My working day
        section Go to work
          Make tea: 5: Me
          Go upstairs: 3: Me
          Do work: 1: Me, Cat
        section Go home
          Go downstairs: 5: Me
          Sit down: 4.5
        """

    @Test func parsesTitleSectionsTasksAndActors() throws {
        let d = try parse(sample)
        #expect(d.title == "My working day")
        #expect(d.sections == ["Go to work", "Go home"])
        #expect(d.tasks.map(\.name) == ["Make tea", "Go upstairs", "Do work", "Go downstairs", "Sit down"])
        #expect(d.tasks.map(\.score) == [5, 3, 1, 5, 4.5])
        #expect(d.tasks[2].actors == ["Me", "Cat"] && d.tasks[4].actors.isEmpty)
        #expect(d.tasks.map(\.section) == [0, 0, 0, 1, 1])
        #expect(d.actors == ["Me", "Cat"])
    }

    @Test func commentsEndStatements() throws {
        let d = try parse("Task: 3: Me # trailing\n# whole line\nOther: 2; ignored")
        #expect(d.tasks.map(\.name) == ["Task", "Other"] && d.tasks[0].actors == ["Me"])
    }

    @Test func locatedErrors() throws {
        let missing = try #require(throws: MermaidError.self) { try parse("section S\n  Make tea") }
        #expect(missing.location == SourceLocation(line: 3, column: 3))
        let score = try #require(throws: MermaidError.self) { try parse("Make tea: high: Me") }
        #expect(score.location == SourceLocation(line: 2, column: 10))
    }

    @Test func layoutPlacesTasksInOrderUnderTheirSections() throws {
        let layout = JourneyLayout.compute(try parse(sample), settings: .init(.object([:])), context: context)
        let frames = layout.tasks.map(\.frame)
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX < $1.minX })
        #expect(layout.sections.count == 2)
        #expect(layout.sections[0].frame.minX == frames[0].minX && layout.sections[0].frame.maxX == frames[2].maxX)
        #expect(layout.sections.allSatisfy { $0.frame.maxY < frames[0].minY })
        #expect(layout.tasks.map(\.colorIndex) == [0, 0, 0, 1, 1])
        // Happier tasks sit higher, all below the axis.
        let faces = layout.tasks.map(\.face.y)
        #expect(faces[0] < faces[1] && faces[1] < faces[2] && faces[0] == faces[3])
        #expect(faces.allSatisfy { $0 > layout.axis.from.y + JourneyLayout.faceRadius })
        #expect(layout.axis.to.x > frames.last!.maxX)
    }

    @Test func actorDotsAndLegendShareColors() throws {
        let layout = JourneyLayout.compute(try parse(sample), settings: .init(.object([:])), context: context)
        #expect(layout.legend.map(\.actor) == ["Me", "Cat"])
        #expect(layout.tasks[2].actorDots.map(\.index) == [0, 1])
        #expect(layout.tasks[2].actorDots.allSatisfy { $0.center.y == layout.tasks[2].frame.minY })
        let palette = JourneyPalette(theme: .default, config: .object([:]))
        #expect(palette.actor(0) == Color(css: "#8FBC8F") && palette.actor(6) == palette.actor(0))
        let themed = JourneyPalette(theme: Theme(.default, variables: ["actor1": "#ff0000"]), config: .object([:]))
        #expect(themed.actor(1) == Color(hex: 0xFF0000))
    }

    @Test func longLabelsGrowTheBoxesAndLegendMargin() throws {
        let long = String(repeating: "A long task name ", count: 4)
        let d = try parse("\(long): 3: A person with a really rather long name\nShort: 3: B")
        let layout = JourneyLayout.compute(d, settings: .init(.object([:])), context: context)
        #expect(layout.tasks[0].frame.height > 50)
        #expect(layout.tasks[0].frame.height >= layout.tasks[0].text.height)
        #expect(layout.leftMargin > 150)
        let legendRight = layout.legend.map { $0.textOrigin.x + $0.text.width }.max()!
        #expect(legendRight < layout.tasks[0].frame.minX)
    }

    @Test func facesMatchScores() {
        let palette = JourneyPalette(theme: .default, config: .object([:]))
        func mouth(_ score: Double) -> Path? {
            guard case .shape(let shape) = JourneyDiagram.face(at: .zero, score: score, palette: palette).last else { return nil }
            return shape.path
        }
        // Smiles curve below their ends, frowns above.
        let smile = try! #require(mouth(5)?.bounds), frown = try! #require(mouth(1)?.bounds)
        #expect(smile.maxY > 2 && frown.minY < 7)
        #expect(mouth(3)?.elements.count == 2)
    }

    @Test func rendersThroughTheRegistry() throws {
        #expect(Mermaid.detectType("journey\n  T: 3") == .journey)
        let scene = try Mermaid.render("journey\n" + sample, options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(scene.svg.contains(">Make tea</text>") && scene.svg.contains(">My working day</text>"))
    }
}
