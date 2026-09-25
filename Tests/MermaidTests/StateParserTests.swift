import Testing
@testable import Mermaid

@Suite("State diagram parsing")
struct StateParserTests {
    func parse(_ body: String, header: String = "stateDiagram-v2") throws -> StateDiagram {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        return try StateParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    func error(_ body: String) -> MermaidError? {
        do {
            _ = try parse(body)
            return nil
        } catch let error as MermaidError {
            return error
        } catch {
            return nil
        }
    }

    @Test func headersSelectTheVersion() throws {
        #expect(try parse("a", header: "stateDiagram").version == 1)
        #expect(try parse("a").version == 2)
        #expect(throws: MermaidError.self) { try parse("a", header: "stateDiagram-v2 LR") }
    }

    @Test func stateDeclarations() throws {
        let d = try parse("""
        stateId
        state "This is a state description" as s2
        s3 : Another description
        state "Title" as s4 : Extra line
        """)
        #expect(d.states.map(\.id) == ["stateId", "s2", "s3", "s4"])
        #expect(d.state("stateId")?.title == "stateId")
        #expect(d.state("s2")?.title == "This is a state description")
        #expect(d.state("s3")?.descriptions == ["Another description"])
        #expect(d.state("s4")?.title == "Title" && d.state("s4")?.body == ["Extra line"])
    }

    @Test func repeatedDescriptionsAccumulate() throws {
        let d = try parse("s1 : Title\ns1 : first line\ns1 : second line")
        #expect(d.state("s1")?.title == "Title")
        #expect(d.state("s1")?.body == ["first line", "second line"])
    }

    @Test func transitionsAndLabels() throws {
        let d = try parse("""
        s1 --> s2
        s2 --> s3: A transition
        s3-->s4 : label: with a colon
        state-1 --> s5
        """)
        #expect(d.transitions.map { "\($0.from)>\($0.to)" } == ["s1>s2", "s2>s3", "s3>s4", "state-1>s5"])
        #expect(d.transitions.map(\.label) == [nil, "A transition", "label: with a colon", nil])
    }

    @Test func startAndEndAreScopedPerComposite() throws {
        let d = try parse("""
        [*] --> First
        First --> [*]
        state First {
            [*] --> second
            second --> [*]
        }
        """)
        #expect(d.state("root_start")?.kind == .start)
        #expect(d.state("root_end")?.kind == .end)
        #expect(d.state("First_start")?.kind == .start && d.state("First_start")?.parent == "First")
        #expect(d.state("First_end")?.parent == "First")
        #expect(d.state("First")?.isComposite == true)
        #expect(d.transitions.map(\.from) == ["root_start", "First", "First_start", "second"])
    }

    @Test func compositesNestAndCanBeNamed() throws {
        let d = try parse("""
        NamedComposite: Another Composite
        state NamedComposite {
            state Second {
                state Third { third }
            }
        }
        state "Long name" as Other {
            x
        }
        state Late
        {
            y
        }
        """)
        #expect(d.state("NamedComposite")?.title == "Another Composite")
        #expect(d.state("Second")?.parent == "NamedComposite")
        #expect(d.state("Third")?.parent == "Second")
        #expect(d.state("third")?.parent == "Third")
        #expect(d.state("Other")?.title == "Long name" && d.state("x")?.parent == "Other")
        #expect(d.state("Late")?.isComposite == true && d.state("y")?.parent == "Late")
    }

    @Test func statesBelongToTheLastCompositeMentioningThem() throws {
        let d = try parse("""
        state A {
            a --> b
        }
        b --> C
        """)
        #expect(d.state("b")?.parent == "A")
        #expect(d.state("C")?.parent == nil)
    }

    @Test func specialStates() throws {
        let d = try parse("""
        state if_state <<choice>>
        state fork_state <<fork>>
        state join_state <<join>>
        state f2 [[fork]]
        """)
        #expect(d.states.map(\.kind) == [.choice, .fork, .join, .fork])
    }

    @Test func notes() throws {
        let d = try parse("""
        State1: The state with a note
        note right of State1
            Important information! You can write
            notes.
        end note
        State1 --> State2
        note left of State2 : This is the note to the left.
        note "Floating" as N1
        """)
        #expect(d.notes.count == 3)
        #expect(d.notes[0].target == "State1" && d.notes[0].position == .right)
        #expect(d.notes[0].text == "Important information! You can write\nnotes.")
        #expect(d.notes[1].position == .left && d.notes[1].text == "This is the note to the left.")
        #expect(d.notes[2].position == .floating && d.notes[2].id == "N1" && d.notes[2].target == nil)
    }

    @Test func concurrencyRegions() throws {
        let d = try parse("""
        state Active {
            [*] --> NumLockOff
            NumLockOff --> NumLockOn : EvNumLockPressed
            --
            direction LR
            [*] --> CapsLockOff
            --
            [*] --> ScrollLockOff
        }
        """)
        #expect(d.regions.map(\.composite) == ["Active", "Active", "Active"])
        let ids = d.regions.map(\.id)
        #expect(d.state("NumLockOff")?.parent == ids[0])
        #expect(d.state("CapsLockOff")?.parent == ids[1])
        #expect(d.state("ScrollLockOff")?.parent == ids[2])
        #expect(d.regions[1].direction == .leftToRight && d.regions[0].direction == nil)
        // Each region scopes its own start state.
        #expect(Set(d.states.filter { $0.kind == .start }.map(\.parent)) == Set(ids))
    }

    @Test func directions() throws {
        let d = try parse("""
        direction LR
        state B {
          direction TB
          a --> b
        }
        """)
        #expect(d.direction == .leftToRight)
        #expect(d.state("B")?.direction == .topToBottom)
    }

    @Test func stylingStatements() throws {
        let d = try parse("""
        classDef movement font-style:italic;
        classDef badBadEvent fill:#f00,color:white,font-weight:bold
        [*] --> Still:::movement
        Crash:::badBadEvent --> [*]
        class Still, Crash movement
        style Moving fill:#0f0,stroke:#333
        """)
        #expect(d.classDefinitions["movement"]?.italic == true)
        #expect(d.classDefinitions["badBadEvent"]?.fill == Color(hex: 0xFF0000))
        #expect(d.state("Still")?.classes == ["movement", "movement"])
        #expect(d.state("Crash")?.classes == ["badBadEvent", "movement"])
        #expect(d.state("Moving")?.style.fill == Color(hex: 0x00FF00))
    }

    @Test func commentsAndMiscellany() throws {
        let d = try parse("""
        %% a comment
        # a hash comment
        s1 --> s2 %% trailing comment
        hide empty description
        scale 350 width
        click s1 "https://example.com" "Tooltip"
        click s2 href "https://example.org"
        accTitle: Title
        """)
        #expect(d.transitions.count == 1 && d.transitions[0].label == nil)
        #expect(d.hidesEmptyDescriptions && d.scaleWidth == 350)
        #expect(d.state("s1")?.link == "https://example.com" && d.state("s1")?.tooltip == "Tooltip")
        #expect(d.state("s2")?.link == "https://example.org")
        #expect(d.accessibility.title == "Title")
    }

    @Test func bracesMayShareLinesWithStatements() throws {
        let d = try parse("state A { a --> b }\nstate B {\n c }; x --> y")
        #expect(d.state("a")?.parent == "A" && d.state("b")?.parent == "A")
        #expect(d.state("c")?.parent == "B" && d.state("x")?.parent == nil)
    }

    @Test func keywordsUsedAsIDs() throws {
        let d = try parse("note --> class\nstate --> end")
        #expect(d.states.map(\.id) == ["note", "class", "state", "end"])
    }

    @Test func errorsAreLocated() {
        let cases: [(String, Int, Int)] = [
            ("a --> ", 1, 6),
            ("state A {\n  a", 1, 7),
            ("}", 1, 1),
            ("a --> b c", 1, 9),
            ("--", 1, 1),
            ("state \"desc\" s1", 1, 14),
            ("note top of A : x", 1, 6),
            ("note left of A\ntext", 1, 6),
            ("direction XY", 1, 11),
            ("state two words {", 1, 11),
            ("state A {\n  A --> b\n}", 2, 3),
        ]
        for (body, line, column) in cases {
            let error = self.error(body)
            #expect(error != nil, "\(body)")
            // The header occupies line 1.
            #expect(error?.location == SourceLocation(line: line + 1, column: column), "\(body): \(String(describing: error))")
        }
    }
}
