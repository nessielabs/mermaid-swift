import Testing
@testable import Mermaid

@Suite("Sequence layout")
struct SequenceLayoutTests {
    func layout(_ body: String, config: ConfigValue = .object([:])) throws -> SequenceLayout {
        let prepared = try Preprocessor.prepare("sequenceDiagram\n" + body)
        let diagram = try SequenceParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
        let context = RenderContext(measurer: ApproximateTextMeasurer(), config: prepared.config.merging(config))
        return SequenceLayoutBuilder.layout(diagram, settings: SequenceSettings(context: context), measurer: context.measurer)
    }

    func contains(_ outer: Rect, _ inner: Rect) -> Bool {
        outer.minX <= inner.minX + 0.001 && outer.maxX >= inner.maxX - 0.001
            && outer.minY <= inner.minY + 0.001 && outer.maxY >= inner.maxY - 0.001
    }

    @Test func headsDoNotOverlapAndKeepDeclarationOrder() throws {
        let l = try layout("""
        participant A as A very long participant label indeed
        actor B
        participant C@{ "type": "database" }
        A->>C: hi
        """)
        #expect(l.actors.map(\.id) == ["A", "B", "C"])
        for (left, right) in zip(l.actors, l.actors.dropFirst()) {
            #expect(left.x < right.x)
            #expect(left.head.maxX < right.head.minX)
            #expect(left.foot?.maxX ?? 0 < right.foot?.minX ?? 1)
        }
        #expect(l.actors[0].head.width >= 150)
    }

    @Test func messagesRunTopToBottomWithLabelsAboveTheirLines() throws {
        let l = try layout("""
        A->>B: first
        B-->>A: second<br/>two lines
        A->>A: self
        B->>C: third message with a label much longer than the default gap
        """)
        let ys = l.messages.map(\.y)
        #expect(ys == ys.sorted() && Set(ys).count == ys.count)
        for m in l.messages where !m.isSelf {
            #expect(m.labelFrame.maxY < m.y)
            #expect(m.labelFrame.minX >= min(m.start.x, m.end.x) && m.labelFrame.maxX <= max(m.start.x, m.end.x))
        }
        for (earlier, later) in zip(l.messages, l.messages.dropFirst()) {
            #expect(later.labelFrame.minY > max(earlier.end.y, earlier.labelFrame.maxY))
        }
    }

    @Test func selfMessageLabelsSitRightOfTheLoopAndClearOfNeighbours() throws {
        let l = try layout("""
        A->>A: a fairly long self message label
        A->>B: hi
        """)
        let loop = l.messages[0]
        let b = try #require(l.actor("B"))
        #expect(loop.start.x == loop.end.x && loop.end.y > loop.start.y)
        #expect(loop.labelFrame.minX > (loop.loopRight ?? .infinity))
        #expect(loop.labelFrame.maxX < b.x)
    }

    @Test func longLabelsWidenTheGapsTheySpan() throws {
        let short = try layout("participant A\nparticipant B\nA->>C: x")
        let long = try layout("participant A\nparticipant B\nA->>C: \(String(repeating: "wide ", count: 40))")
        let span = { (l: SequenceLayout) in (l.actor("C")?.x ?? 0) - (l.actor("A")?.x ?? 0) }
        #expect(span(long) > span(short) + 300)
        // The widening is shared by both gaps it spans.
        let gaps = [long.actors[1].x - long.actors[0].x, long.actors[2].x - long.actors[1].x]
        #expect(abs(gaps[0] - gaps[1]) < 1)
        #expect(long.messages[0].label.width + 20 <= abs(long.messages[0].end.x - long.messages[0].start.x))
    }

    @Test func notesArePlacedBesideOrOverParticipants() throws {
        let l = try layout("""
        participant A
        participant B
        Note left of A: left
        Note right of A: a right note that is rather long
        Note over B: over
        Note over A,B: spanning
        """)
        let a = try #require(l.actor("A")), b = try #require(l.actor("B"))
        let n = l.notes.map(\.frame)
        #expect(n[0].maxX < a.x)
        #expect(n[1].minX > a.x && n[1].maxX < b.x)
        #expect(abs(n[2].midX - b.x) < 0.001)
        #expect(n[3].minX < a.x && n[3].maxX > b.x)
        for (upper, lower) in zip(n, n.dropFirst()) { #expect(upper.maxY < lower.minY) }
        for note in l.notes { #expect(note.text.width <= note.frame.width) }
    }

    @Test func activationsNestAndMeetTheirMessages() throws {
        let l = try layout("""
        A->>+B: one
        A->>+B: two
        B-->>-A: three
        B-->>-A: four
        """)
        #expect(l.activations.count == 2)
        let inner = try #require(l.activations.first { $0.depth == 1 })
        let outer = try #require(l.activations.first { $0.depth == 0 })
        #expect(contains(outer.frame.insetBy(dx: -20, dy: 0), inner.frame))
        #expect(inner.frame.minY > outer.frame.minY && inner.frame.maxY < outer.frame.maxY)
        #expect(inner.frame.minX > outer.frame.minX)
        // Arrows meet the facing side of the bars.
        #expect(abs(l.messages[0].end.x - outer.frame.minX) < 0.001)
        #expect(abs(l.messages[2].start.x - outer.frame.minX) < 0.001)
        #expect(outer.frame.minY <= l.messages[0].y && outer.frame.maxY >= l.messages[3].y)
    }

    @Test func framesEncloseTheirStatementsAndNest() throws {
        let l = try layout("""
        A->>B: before
        loop Every minute
          A->>B: ping
          alt ok
            B->>C: good
          else a failure condition that is long
            B->>B: retry
            Note right of B: note
          end
        end
        A->>B: after
        """)
        let loop = try #require(l.frames.first { $0.kind == .loop })
        let alt = try #require(l.frames.first { $0.kind == .alt })
        #expect(contains(loop.frame, alt.frame) && alt.depth == loop.depth + 1)
        #expect(alt.frame.minX > loop.frame.minX && alt.frame.maxY < loop.frame.maxY)
        for m in l.messages[1...3] {
            #expect(contains(loop.frame, m.labelFrame))
            #expect(loop.frame.minY < m.y && m.y < loop.frame.maxY)
        }
        for m in l.messages[2...3] { #expect(contains(alt.frame, m.labelFrame)) }
        #expect(contains(alt.frame, l.notes[0].frame))
        #expect(l.messages[0].y < loop.frame.minY && l.messages[4].labelFrame.minY > loop.frame.maxY)
        let divider = try #require(alt.dividers.first)
        #expect(l.messages[2].y < divider.y && divider.y < l.messages[3].start.y)
        #expect(contains(alt.frame, divider.labelFrame))
        #expect(alt.tagFrame.maxY <= l.messages[2].labelFrame.minY)
    }

    @Test func longConditionsWrapWithinTheirFrame() throws {
        let l = try layout("""
        loop \(String(repeating: "retry ", count: 60))
          A->>A: x
        end
        """)
        let frame = try #require(l.frames.first)
        let condition = try #require(frame.condition)
        #expect(condition.lines.count > 1)
        #expect(frame.conditionFrame.maxX <= frame.frame.maxX && condition.width <= frame.conditionFrame.width + 0.001)
        #expect(frame.conditionFrame.minX >= frame.tagFrame.maxX)
    }

    @Test func createdParticipantsAppearAtTheirMessage() throws {
        let l = try layout("""
        A->>B: hi
        create participant C
        A->>C: make
        destroy C
        C-xA: bye
        """)
        let c = try #require(l.actor("C"))
        let make = l.messages[1]
        #expect(abs(c.head.midY - make.y) < 0.001)
        #expect(abs(make.end.x - c.head.minX) < 0.001)
        #expect(c.lifelineTop == c.head.maxY && c.head.minY > l.messages[0].y)
        #expect(c.isDestroyed && c.foot == nil)
        #expect(c.lifelineBottom > l.messages[2].y && c.lifelineBottom < (l.actor("A")?.lifelineBottom ?? 0))
    }

    @Test func boxesContainTheirParticipantsAndTitles() throws {
        let l = try layout("""
        box Aqua A very long box title that is wider than its lone participant
        participant A
        end
        box Group
        participant B
        participant C
        end
        A->>C: hi
        """)
        #expect(l.groups.count == 2)
        let (first, second) = (l.groups[0], l.groups[1])
        #expect(first.frame.maxX < second.frame.minX)
        #expect(contains(first.frame, try #require(l.actor("A")).head))
        #expect(contains(second.frame, try #require(l.actor("C")).head))
        #expect((first.title?.width ?? 0) <= first.frame.width)
        #expect((l.actors.first?.head.minY ?? 0) > first.titleFrame.maxY)
        #expect(first.frame.maxY >= l.actors.compactMap(\.foot?.maxY).max() ?? 0)
    }

    @Test func settingsChangeTheLayout() throws {
        let body = "A->>B: hi\nA->>C: there"
        let plain = try layout(body)
        let config: ConfigValue = .object(["sequence": .object([
            "mirrorActors": .bool(false), "actorMargin": .number(120), "hideUnusedParticipants": .bool(true),
        ])])
        let custom = try layout("participant Unused\n" + body, config: config)
        #expect(plain.actors.allSatisfy { $0.foot != nil })
        #expect(custom.actors.allSatisfy { $0.foot == nil })
        #expect(custom.actor("Unused") == nil)
        #expect(custom.actors[1].x - custom.actors[0].x > plain.actors[1].x - plain.actors[0].x)
    }

    @Test func wrappingKeepsLabelsNarrow() throws {
        let text = String(repeating: "word ", count: 30)
        let wrapped = try layout("A->>B: wrap:\(text)")
        let unwrapped = try layout("A->>B: \(text)")
        #expect(wrapped.messages[0].label.lines.count > 1)
        #expect(unwrapped.messages[0].label.lines.count == 1)
        let directive = try layout("%%{wrap}%%\nA->>B: \(text)")
        #expect(directive.messages[0].label.lines.count > 1)
    }

    @Test func autonumberBadgesSitOnTheSender() throws {
        let l = try layout("autonumber 5 5\nA->>B: x\nB-->>A: y\nautonumber off\nA->>B: z")
        #expect(l.messages.compactMap(\.number).map(\.text.lines.first?.runs.first?.text) == ["5", "10"])
        #expect(l.messages[0].number?.center.x == l.messages[0].start.x)
        #expect(l.messages[2].number == nil)
    }
}
