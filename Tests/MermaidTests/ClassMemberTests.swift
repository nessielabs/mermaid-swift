import Testing
@testable import Mermaid

@Suite("Class members")
struct ClassMemberTests {
    @Test func attributesWithVisibility() {
        let cases: [(String, ClassMember.Visibility, String)] = [
            ("+String owner", .public, "String owner"), ("-int size", .private, "int size"),
            ("#List items", .protected, "List items"), ("~Map cache", .package, "Map cache"),
            ("noOfVertices", .none, "noOfVertices"),
        ]
        for (text, visibility, name) in cases {
            let member = ClassMember(parsing: text)
            #expect(member.kind == .attribute, "\(text)")
            #expect(member.visibility == visibility, "\(text)")
            #expect(member.name == name, "\(text)")
            #expect(member.displayText == text, "\(text)")
        }
    }

    @Test func attributeClassifiers() {
        let field = ClassMember(parsing: "+String someField$")
        #expect(field.classifier == .static && field.name == "String someField")
        #expect(field.displayText == "+String someField")
        #expect(ClassMember(parsing: "int count*").classifier == .abstract)
    }

    @Test func methodsWithParametersAndReturnTypes() {
        let deposit = ClassMember(parsing: "+deposit(amount) bool")
        #expect(deposit.kind == .method && deposit.visibility == .public)
        #expect(deposit.name == "deposit" && deposit.parameters == "amount" && deposit.returnType == "bool")
        #expect(deposit.displayText == "+deposit(amount) : bool")
        let bare = ClassMember(parsing: "draw()")
        #expect(bare.kind == .method && bare.parameters.isEmpty && bare.returnType.isEmpty)
        #expect(bare.displayText == "draw()")
    }

    @Test func methodClassifiersAfterParenthesesOrReturnType() {
        let cases: [(String, ClassMember.Classifier, String, String)] = [
            ("someAbstractMethod()*", .abstract, "", "someAbstractMethod()"),
            ("someAbstractMethod() int*", .abstract, "int", "someAbstractMethod() : int"),
            ("someStaticMethod()$", .static, "", "someStaticMethod()"),
            ("someStaticMethod() String$", .static, "String", "someStaticMethod() : String"),
            ("someStaticMethod()$ String", .static, "String", "someStaticMethod() : String"),
        ]
        for (text, classifier, returnType, display) in cases {
            let member = ClassMember(parsing: text)
            #expect(member.classifier == classifier, "\(text)")
            #expect(member.returnType == returnType, "\(text)")
            #expect(member.displayText == display, "\(text)")
        }
    }

    @Test func packageVisibilityIsNotAGeneric() {
        let member = ClassMember(parsing: "~internal() List~int~")
        #expect(member.visibility == .package)
        #expect(member.displayText == "~internal() : List<int>")
    }

    @Test func genericsInEveryPosition() {
        #expect(ClassMember(parsing: "List~int~ position").displayText == "List<int> position")
        #expect(ClassMember(parsing: "setPoints(List~int~ points)").displayText == "setPoints(List<int> points)")
        #expect(ClassMember(parsing: "+getDistanceMatrix() List~List~int~~").displayText
            == "+getDistanceMatrix() : List<List<int>>")
    }

    @Test func genericNotation() {
        #expect(ClassGenerics.render("List~int~") == "List<int>")
        #expect(ClassGenerics.render("List~List~int~~") == "List<List<int>>")
        #expect(ClassGenerics.render("Map~K, V~") == "Map<K, V>")
        #expect(ClassGenerics.render("a~b~, c~d~") == "a<b>, c<d>")
        #expect(ClassGenerics.render("no generics") == "no generics")
        #expect(ClassGenerics.render("lone~tilde") == "lone~tilde")
    }

    @Test func textWithParenthesisOnlyAtTheStartIsAnAttribute() {
        #expect(ClassMember(parsing: ")odd").kind == .attribute)
    }
}
