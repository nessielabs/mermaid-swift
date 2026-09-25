import Testing
@testable import Mermaid

@Suite("Class diagram parsing")
struct ClassParserTests {
    func parse(_ body: String, header: String = "classDiagram") throws -> ClassDiagram {
        let parsed = try Mermaid.parse(header + "\n" + body)
        return try #require(parsed.diagram as? ClassDiagram)
    }

    @Test func bothHeadersAreRegistered() throws {
        #expect(Mermaid.detectType("classDiagram\n A") == .classDiagram)
        #expect(Mermaid.detectType("classDiagram-v2\n A") == .classDiagram)
        #expect(try parse("class A", header: "classDiagram-v2").classes.map(\.id) == ["A"])
    }

    @Test func classDeclarationForms() throws {
        let d = try parse("""
        class Animal
        class Car["Car with *! symbols"]
        class `Animal Class!`
        class Square~Shape~
        class Duck:::pink
        class Shape <<interface>>
        class Ünïcode_名前-1
        """)
        #expect(d.classes.map(\.id) == ["Animal", "Car", "Animal Class!", "Square", "Duck", "Shape", "Ünïcode_名前-1"])
        #expect(d.class("Car")?.label == "Car with *! symbols")
        #expect(d.class("Square")?.genericType == "Shape")
        #expect(d.class("Square")?.displayName == "Square<Shape>")
        #expect(d.class("Duck")?.cssClasses == ["pink"])
        #expect(d.class("Shape")?.annotations == ["interface"])
    }

    @Test func classBodies() throws {
        let d = try parse("""
        class BankAccount{
            <<service>>
            +String owner
            +BigDecimal balance
            +deposit(amount) bool
            +withdrawal(amount)
        }
        class Empty {
        }
        class OneLine { +int x }
        class Styled:::hot <<entity>> {
          id
        }
        """)
        let account = try #require(d.class("BankAccount"))
        #expect(account.annotations == ["service"])
        #expect(account.attributes.map(\.displayText) == ["+String owner", "+BigDecimal balance"])
        #expect(account.methods.map(\.displayText) == ["+deposit(amount) : bool", "+withdrawal(amount)"])
        #expect(d.class("Empty")?.attributes.isEmpty == true)
        #expect(d.class("OneLine")?.attributes.map(\.name) == ["int x"])
        #expect(d.class("Styled")?.cssClasses == ["hot"] && d.class("Styled")?.annotations == ["entity"])
    }

    @Test func memberLines() throws {
        let d = try parse("""
        BankAccount : +String owner
        BankAccount: +deposit(amount)
        Square~Shape~ : -List~string~ messages
        Shape : <<interface>>
        """)
        #expect(d.class("BankAccount")?.attributes.count == 1)
        #expect(d.class("BankAccount")?.methods.count == 1)
        #expect(d.class("Square")?.genericType == "Shape")
        #expect(d.class("Square")?.attributes.first?.displayText == "-List<string> messages")
        #expect(d.class("Shape")?.annotations == ["interface"])
    }

    @Test func standaloneAnnotations() throws {
        let d = try parse("class Shape\n<<interface>> Shape\n<< abstract >> Later")
        #expect(d.class("Shape")?.annotations == ["interface"])
        #expect(d.class("Later")?.annotations == ["abstract"])
    }

    @Test func everyRelationType() throws {
        typealias End = ClassDiagram.RelationEnd
        let cases: [(String, End, ClassDiagram.LineStyle, End)] = [
            ("<|--", .inheritance, .solid, .none), ("*--", .composition, .solid, .none),
            ("o--", .aggregation, .solid, .none), ("-->", .none, .solid, .association),
            ("--", .none, .solid, .none), ("..>", .none, .dashed, .association),
            ("..|>", .none, .dashed, .inheritance), ("..", .none, .dashed, .none),
            ("<--", .association, .solid, .none), ("<..", .association, .dashed, .none),
            ("<|..", .inheritance, .dashed, .none), ("--|>", .none, .solid, .inheritance),
            ("--*", .none, .solid, .composition), ("--o", .none, .solid, .aggregation),
            ("<|--|>", .inheritance, .solid, .inheritance), ("<-->", .association, .solid, .association),
            ("*--o", .composition, .solid, .aggregation), ("o..*", .aggregation, .dashed, .composition),
            ("<..>", .association, .dashed, .association),
        ]
        for (op, left, line, right) in cases {
            // Without spaces an `o` end would merge into the class name.
            let compact = op.hasPrefix("o") || op.hasSuffix("o") ? [] : ["A\(op)B"]
            for source in ["A \(op) B"] + compact {
                let relation = try #require(try parse(source).relations.first, "\(source)")
                #expect(relation.from == "A" && relation.to == "B", "\(source)")
                #expect(relation.fromEnd == left && relation.line == line && relation.toEnd == right, "\(source)")
            }
        }
    }

    @Test func relationLabelsAndCardinalities() throws {
        let d = try parse("""
        Customer "1" --> "*" Ticket
        Student "1" --> "1..*" Course : enrolls
        Galaxy --> "many" Star : Contains
        classA <|-- classB : implements
        Order "0..1" *-- LineItem
        """)
        let r = d.relations
        #expect(r[0].fromCardinality == "1" && r[0].toCardinality == "*" && r[0].label == nil)
        #expect(r[1].toCardinality == "1..*" && r[1].label == "enrolls")
        #expect(r[2].fromCardinality == nil && r[2].toCardinality == "many" && r[2].label == "Contains")
        #expect(r[3].label == "implements")
        #expect(r[4].fromCardinality == "0..1" && r[4].toCardinality == nil)
    }

    @Test func relationsDeclareClassesWithGenerics() throws {
        let d = try parse("List~int~ <|-- `My List` : extends\nfoo.bar --> a-b")
        #expect(d.classes.map(\.id) == ["List", "My List", "foo.bar", "a-b"])
        #expect(d.class("List")?.genericType == "int")
    }

    @Test func aggregationNeedsAWordBoundary() throws {
        let d = try parse("A --> order\nB o-- C\nD --o E")
        #expect(d.relations[0].to == "order" && d.relations[0].toEnd == .association)
        #expect(d.relations[1].fromEnd == .aggregation)
        #expect(d.relations[2].toEnd == .aggregation && d.relations[2].to == "E")
    }

    @Test func lollipopInterfaces() throws {
        let d = try parse("""
        class Class01
        Class01 --() bar
        Class02 --() bar
        foo ()-- Class01
        A ()--* B
        """)
        #expect(d.interfaces.map(\.label) == ["bar", "bar", "foo"])
        #expect(d.interfaces.map(\.classID) == ["Class01", "Class02", "Class01"])
        #expect(d.relations[0].to == "interface0" && d.relations[0].toEnd == .lollipop)
        #expect(d.relations[2].from == "interface2" && d.relations[2].fromEnd == .lollipop)
        // A lollipop facing another decoration relates two classes.
        #expect(d.relations[3].from == "A" && d.relations[3].to == "B")
        #expect(d.class("bar") == nil && d.class("foo") == nil && d.class("A") != nil)
    }
}
