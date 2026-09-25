import Testing
@testable import Mermaid

@Suite("Class diagram errors")
struct ClassErrorTests {
    /// Parses `body` after a `classDiagram` header on line 1 and returns
    /// the error it throws.
    func error(_ body: String) -> MermaidError? {
        do {
            _ = try Mermaid.parse("classDiagram\n" + body)
            return nil
        } catch let error as MermaidError {
            return error
        } catch {
            return nil
        }
    }

    @Test func errorsPointAtTheProblem() {
        let cases: [(String, Int, Int, String)] = [
            ("A -> B", 2, 3, "Expected a relation"),
            ("A --> ", 2, 6, "class name after the relation"),
            ("A --> B extra", 2, 9, "Unexpected 'e'"),
            ("  class", 2, 8, "Expected a class name"),
            ("class A[\"x\"", 2, 8, "Expected ']'"),
            ("class A[x]", 2, 9, "a label in double quotes"),
            ("class A {\n  +x", 2, 9, "Class 'A' is missing its closing '}'"),
            ("class A {\n  { nested", 3, 3, "Unexpected '{'"),
            ("namespace N {\n class A", 2, 10, "Namespace 'N' is missing its closing '}'"),
            ("namespace N", 2, 12, "Expected '{'"),
            ("}", 2, 1, "without an open namespace"),
            ("direction XY", 2, 11, "Unknown direction 'XY'"),
            ("note \"unterminated", 2, 6, "Unterminated string"),
            ("note for", 2, 9, "Expected a class name"),
            ("class `Open", 2, 7, "Unterminated '`'"),
            ("class List~int", 2, 11, "Unterminated '~'"),
            ("<<interface Shape", 2, 1, "Unterminated '<<'"),
            ("<<>> Shape", 2, 1, "Empty annotation"),
            ("click A", 2, 8, "Expected 'href' or 'call'"),
            ("link A \"u\" _nowhere", 2, 12, "Unknown link target"),
            ("cssClass A pink", 2, 10, "class ids in double quotes"),
            ("class A:::", 2, 11, "style class name"),
            ("-->", 2, 1, "Expected a statement"),
        ]
        for (source, line, column, message) in cases {
            guard let error = error(source) else {
                Issue.record("no error for \(source)")
                continue
            }
            #expect(error.kind == .syntax, "\(source)")
            #expect(error.location == SourceLocation(line: line, column: column), "\(source): \(error)")
            #expect(error.message.contains(message), "\(source): \(error.message)")
        }
    }

    @Test func malformedInputNeverCrashes() {
        let fragments = ["class", "{", "}", "<<", ">>", "\"", "`", "~", ":::", "-->", "..", "()", "note", "for",
                         "namespace", "A", "B", ":", "[", "]", "o", "*", "|>", "<|", "click", "href", "call(",
                         "%%", ";", "direction", "LR", "\n", " "]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<400 {
            let body = (0..<Int.random(in: 1...12, using: &generator))
                .map { _ in fragments.randomElement(using: &generator)! }.joined(separator: " ")
            let source = "classDiagram\n" + body
            if let scene = try? Mermaid.render(source, options: RenderOptions(measurer: ApproximateTextMeasurer())) {
                #expect(scene.size.width.isFinite && scene.size.height.isFinite, "\(body)")
            }
        }
    }
}
