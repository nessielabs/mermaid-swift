import Testing
@testable import Mermaid

@Suite("Sequence parsing")
struct SequenceParserTests {
    typealias D = SequenceDiagram

    func parse(_ body: String, header: String = "sequenceDiagram") throws -> SequenceDiagram {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try SequenceParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    func error(_ body: String) -> MermaidError? {
        do { _ = try parse(body); return nil } catch let error as MermaidError { return error } catch { return nil }
    }

    @Test func participantsAppearInOrderOfFirstMention() throws {
        let d = try parse("""
        participant Bob
        Alice->>Bob: Hi
        Bob->>Carol: Hey
        """)
        #expect(d.participants.map(\.id) == ["Bob", "Alice", "Carol"])
        #expect(d.participants.allSatisfy { $0.kind == .participant && $0.label == $0.id })
    }

    @Test func aliasesAndActors() throws {
        let d = try parse("""
        participant A as Alice<br/>Johnson
        actor J as John
        participant Long Name
        participant "Quoted" as "Q label"
        PARTICIPANT X AS wrap:Wrapped label
        """)
        #expect(d.participant("A")?.label == "Alice<br/>Johnson")
        #expect(d.participant("J")?.kind == .actor)
        #expect(d.participant("J")?.label == "John")
        #expect(d.participant("Long Name") != nil)
        #expect(d.participant("Quoted")?.label == "Q label")
        #expect(d.participant("X")?.label == "Wrapped label")
        #expect(d.participant("X")?.wrap == true)
    }

    @Test func participantTypesFromMetadata() throws {
        let d = try parse("""
        participant A@{ "type" : "boundary" }
        participant B@{ "type": "control", "alias": "Inline" }
        actor C@{ "type": "database" } as External
        participant D@{ type: queue }
        participant E@{ "type": "entity", "alias": "Internal" } as Wins
        participant F@{ "type": "collections" }
        """)
        #expect(d.participants.map(\.kind) == [.boundary, .control, .database, .queue, .entity, .collections])
        #expect(d.participant("B")?.label == "Inline")
        #expect(d.participant("C")?.label == "External")
        #expect(d.participant("E")?.label == "Wins")
        #expect(throws: MermaidError.self) { try parse("participant A@{ \"type\": \"blob\" }") }
        #expect(throws: MermaidError.self) { try parse("participant A@{ \"type\": \"queue\"") }
    }

    @Test func redeclarationWithoutAliasKeepsParticipant() throws {
        let d = try parse("""
        participant A as Alice
        participant A
        actor A
        """)
        #expect(d.participants.count == 1)
        #expect(d.participant("A")?.label == "Alice")
        #expect(d.participant("A")?.kind == .participant)
    }

    @Test func everyArrow() throws {
        let cases: [(String, D.LineStyle, D.ArrowHead, D.ArrowHead)] = [
            ("->", .solid, .none, .none), ("-->", .dotted, .none, .none),
            ("->>", .solid, .none, .arrow), ("-->>", .dotted, .none, .arrow),
            ("<<->>", .solid, .arrow, .arrow), ("<<-->>", .dotted, .arrow, .arrow),
            ("-x", .solid, .none, .cross), ("--x", .dotted, .none, .cross), ("-X", .solid, .none, .cross),
            ("-)", .solid, .none, .async), ("--)", .dotted, .none, .async),
            ("-|\\", .solid, .none, .halfTop), ("--|\\", .dotted, .none, .halfTop),
            ("-|/", .solid, .none, .halfBottom), ("--|/", .dotted, .none, .halfBottom),
            ("-\\\\", .solid, .none, .stickTop), ("--\\\\", .dotted, .none, .stickTop),
            ("-//", .solid, .none, .stickBottom), ("--//", .dotted, .none, .stickBottom),
            ("/|-", .solid, .halfTop, .none), ("/|--", .dotted, .halfTop, .none),
            ("\\|-", .solid, .halfBottom, .none), ("\\|--", .dotted, .halfBottom, .none),
            ("//-", .solid, .stickTop, .none), ("//--", .dotted, .stickTop, .none),
            ("\\\\-", .solid, .stickBottom, .none), ("\\\\--", .dotted, .stickBottom, .none),
        ]
        for (arrow, line, tail, head) in cases {
            let message = try #require(try parse("A\(arrow)B: text").messages.first, "\(arrow)")
            #expect(message.from == "A" && message.to == "B" && message.text == "text", "\(arrow)")
            #expect(message.line == line && message.tail == tail && message.head == head, "\(arrow)")
        }
    }

    @Test func messageModifiers() throws {
        let m = try parse("""
        Alice ->>+ John: Hello
        John-->>-Alice: Great
        A->>()B: central target
        A()->>B: central source
        A()->>()B: both
        """).messages
        #expect(m[0].activatesTarget && m[0].from == "Alice" && m[0].to == "John")
        #expect(m[1].deactivatesSource)
        #expect(m[2].centralTarget && !m[2].centralSource)
        #expect(m[3].centralSource && !m[3].centralTarget)
        #expect(m[4].centralSource && m[4].centralTarget)
    }

    @Test func namesWithDashesAndKeywordsKeepTheirText() throws {
        let d = try parse("""
        billing-service-ts->>auth-xyz: hi
        endpoint->>optimizer: go
        Note ->> loop: named like keywords
        """)
        #expect(d.participants.map(\.id) == ["billing-service-ts", "auth-xyz", "endpoint", "optimizer", "Note", "loop"])
    }

    @Test func messageTextKeepsColonsAndWrapPrefixes() throws {
        let m = try parse("""
        A->>B: time: 10:30
        A->>B:wrap: long text
        A->>B: nowrap: short
        A->>B:
        A->>B
        """).messages
        #expect(m[0].text == "time: 10:30")
        #expect(m[1].text == "long text" && m[1].wrap == true)
        #expect(m[2].text == "short" && m[2].wrap == false)
        #expect(m[3].text.isEmpty && m[4].text.isEmpty)
    }

    @Test func semicolonsSeparateStatementsButNotEntities() throws {
        let m = try parse("A->>B: one; B->>A: I #9829; you #59; really").messages
        #expect(m.count == 2)
        #expect(m[1].text == "I #9829; you #59; really")
    }

    @Test func commentsAreIgnored() throws {
        let d = try parse("""
        %% a comment
        A->>B: hi %% trailing comment
        """)
        #expect(d.messages.map(\.text) == ["hi"])
    }

    @Test func notes() throws {
        let d = try parse("""
        Note left of A: left
        note right of B: right
        Note over A: over one
        Note over A,B: over two
        NOTE OVER A , A: same twice
        Note over B: wrap: wrapped
        """)
        let notes = d.statements.compactMap { if case .note(let n) = $0 { n } else { nil } }
        #expect(notes.map(\.placement) == [.leftOf("A"), .rightOf("B"), .over("A", nil), .over("A", "B"), .over("A", nil), .over("B", nil)])
        #expect(notes[0].text == "left" && notes[5].wrap == true)
        #expect(throws: MermaidError.self) { try parse("Note left of A,B: two") }
        #expect(throws: MermaidError.self) { try parse("Note above A: x") }
        #expect(throws: MermaidError.self) { try parse("Note over A") }
    }

    @Test func blocksNestWithSections() throws {
        let d = try parse("""
        loop Every minute
          A->>B: ping
          alt is sick
            B->>A: bad
          else is well
            B->>A: good
          else
            B->>A: meh
          end
        end
        par a
          A->>B: 1
        and b
          A->>C: 2
        end
        critical connect
          A->>B: c
        option timeout
          A->>A: log
        end
        opt extra
        end
        break fails
          A->>B: stop
        end
        par_over over
          A->>B: x
        end
        """)
        let blocks = d.statements.compactMap { if case .block(let b) = $0 { b } else { nil } }
        #expect(blocks.map(\.kind) == [.loop, .par, .critical, .opt, .break, .parOver])
        #expect(blocks[0].sections[0].label == "Every minute")
        guard case .block(let alt) = blocks[0].sections[0].statements[1] else { Issue.record("expected alt"); return }
        #expect(alt.sections.map(\.label) == ["is sick", "is well", ""])
        #expect(blocks[1].sections.map(\.label) == ["a", "b"])
        #expect(blocks[2].sections.map(\.label) == ["connect", "timeout"])
        #expect(blocks[3].sections[0].statements.isEmpty)
    }

    @Test func rectColors() throws {
        let d = try parse("""
        rect rgb(191, 223, 255)
          rect rgba(0, 0, 255, .1)
            A->>B: hi
          end
        end
        rect
        end
        """)
        let blocks = d.statements.compactMap { if case .block(let b) = $0 { b } else { nil } }
        #expect(blocks[0].kind == .rect && blocks[0].color == Color(css: "rgb(191, 223, 255)"))
        guard case .block(let inner) = blocks[0].sections[0].statements[0] else { Issue.record("expected rect"); return }
        #expect(inner.color?.alpha == 0.1)
        #expect(blocks[1].color == nil)
    }

    @Test func boxesGroupParticipants() throws {
        let d = try parse("""
        box Purple Alice & John
        participant A
        actor J
        end
        box Another Group
        participant B
        end
        box rgb(33,66,99)
        participant C
        end
        box transparent Aqua
        participant D
        end
        box #ff000080 Hex
        participant E
        end
        A->>F: hi
        """)
        #expect(d.boxes.map(\.title) == ["Alice & John", "Another Group", nil, "Aqua", "Hex"])
        #expect(d.boxes[0].color == Color(css: "purple") && d.boxes[1].color == nil && d.boxes[3].color == nil)
        #expect(d.boxes[2].color == Color(css: "rgb(33,66,99)") && d.boxes[4].color?.alpha ?? 1 < 1)
        #expect(d.boxes[0].participants == ["A", "J"])
        #expect(d.participant("F")?.box == nil && d.participant("J")?.box == 0)
        #expect(throws: MermaidError.self) { try parse("box A\nA->>B: x\nend") }
        #expect(throws: MermaidError.self) { try parse("box A\nparticipant X\nend\nbox B\nparticipant X\nend") }
        #expect(throws: MermaidError.self) { try parse("box A\nbox B\nend\nend") }
    }

    @Test func activations() throws {
        let d = try parse("""
        A->>B: hi
        activate B
        activate B
        deactivate B
        deactivate B
        """)
        #expect(d.statements.count == 5)
        #expect(d.statements[1] == .activate("B") && d.statements[4] == .deactivate("B"))
        let unbalanced = error("A->>B: hi\ndeactivate B")
        #expect(unbalanced?.kind == .semantic && unbalanced?.location?.line == 3)
        #expect(throws: MermaidError.self) { try parse("A-->>-B: no active sender") }
    }

    @Test func autonumbering() throws {
        let m = try parse("""
        A->>B: 1
        autonumber
        A->>B: 2
        autonumber 10
        A->>B: 10
        autonumber 1.5 0.25
        A->>B: a
        A->>B: b
        autonumber off
        A->>B: hidden
        """).messages
        #expect(m.map(\.showsNumber) == [false, true, true, true, true, false])
        #expect(m.map(\.number) == [1, 2, 10, 1.5, 1.75, 2])
        #expect(throws: MermaidError.self) { try parse("autonumber x") }
    }

    @Test func createAndDestroy() throws {
        let d = try parse("""
        Alice->>Bob: Hello
        create participant Carl
        Alice->>Carl: Hi Carl!
        create actor D as Donald
        Carl->>D: Hi!
        destroy Carl
        Alice-xCarl: We are too many
        destroy Bob
        Bob->>Alice: I agree
        """)
        let m = d.messages
        #expect(d.participant("Carl")?.isCreated == true && d.participant("D")?.kind == .actor)
        #expect(d.participant("D")?.label == "Donald")
        #expect(m[1].createsTarget && m[2].createsTarget)
        #expect(m[3].destroysTarget && m[4].destroysSource)
        #expect(throws: MermaidError.self) { try parse("create participant C\nA->>B: wrong") }
        #expect(throws: MermaidError.self) { try parse("A->>B: x\ncreate participant B\nA->>B: again") }
        #expect(throws: MermaidError.self) { try parse("destroy C\nA->>B: wrong") }
        #expect(throws: MermaidError.self) { try parse("create participant C") }
    }

    @Test func titleLinksAndMenus() throws {
        let d = try parse("""
        title Checkout flow
        participant Alice
        link Alice: Dashboard @ https://dashboard.contoso.com/alice
        links Alice: {"Wiki": "https://wiki.contoso.com/alice"}
        links Alice: not json
        properties Alice: {"class": "x"}
        details Alice: some-id
        """)
        #expect(d.title == "Checkout flow")
        #expect(d.participant("Alice")?.links.map(\.name) == ["Dashboard", "Wiki"])
        #expect(try parse("title: Legacy").title == "Legacy")
    }

    @Test func accessibilityIsExtracted() throws {
        let d = try parse("accTitle: Title\naccDescr: Description\nA->>B: x")
        #expect(d.accessibility.title == "Title" && d.accessibility.description == "Description")
    }

    @Test func errorsAreLocated() throws {
        let cases: [(String, Int, Int)] = [
            ("A->>B: ok\n  bogus statement", 3, 3),
            ("loop x\nA->>B: y", 2, 1),
            ("A->>B: x\nend", 3, 1),
            ("else nope", 2, 1),
            ("A->>B: x\nand y", 3, 1),
            ("option z", 2, 1),
            ("participant A:B", 2, 13),
            ("A->>B: fine; nonsense", 2, 14),
            ("end now", 2, 4),
        ]
        for (body, line, column) in cases {
            let e = try #require(error(body), "\(body)")
            #expect(e.location == SourceLocation(line: line, column: column), "\(body): \(e)")
        }
    }
}
