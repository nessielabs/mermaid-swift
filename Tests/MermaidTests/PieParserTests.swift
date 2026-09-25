import Testing
@testable import Mermaid

@Suite("Pie parsing")
struct PieParserTests {
    func parse(_ source: String) throws -> PieDiagram {
        let prepared = try Preprocessor.prepare(source)
        return try PieParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func slicesKeepSourceOrderAndDecimals() throws {
        let pie = try parse("""
        pie title Pets adopted by volunteers
            "Dogs" : 386
            "Cats" : 85.5
            'Rats' : 15
        """)
        #expect(pie.title == "Pets adopted by volunteers")
        #expect(!pie.showData)
        #expect(pie.slices.map(\.label) == ["Dogs", "Cats", "Rats"])
        #expect(pie.slices.map(\.value) == [386, 85.5, 15])
    }

    @Test func showDataAndTitleMayShareTheHeader() throws {
        let pie = try parse("pie showData title Key elements\n\"A\": 1")
        #expect(pie.showData && pie.title == "Key elements")
        let separate = try parse("pie showData\n  title Key elements in Product X\n  \"Iron\" :  5")
        #expect(separate.showData && separate.title == "Key elements in Product X")
        #expect(separate.slices == [.init(label: "Iron", value: 5)])
        #expect(try parse("pie title \"Quoted title\"").title == "Quoted title")
    }

    @Test func accessibilityCommentsAndDuplicates() throws {
        let pie = try parse("""
        pie
            accTitle: Pets
            accDescr: Adopted pets by species
            %% a comment line
            "Dogs" : 3 %% trailing comment
            "Dogs" : 9
            "Zero" : 0
            "100%% real" : 2
        """)
        #expect(pie.accessibility.title == "Pets")
        #expect(pie.accessibility.description == "Adopted pets by species")
        // A repeated label keeps its first value, as in mermaid.js.
        #expect(pie.slices.map(\.label) == ["Dogs", "Zero", "100%% real"])
        #expect(pie.slices.map(\.value) == [3, 0, 2])
    }

    @Test func escapedQuotesInLabels() throws {
        let pie = try parse(#"pie"# + "\n" + #""Say \"hi\"" : 1"#)
        #expect(pie.slices[0].label == #"Say "hi""#)
    }

    @Test func negativeValuesAreLocatedErrors() throws {
        let error = try #require(throws: MermaidError.self) { try parse("pie\n  \"Dogs\" : -4") }
        #expect(error.kind == .semantic)
        #expect(error.location == SourceLocation(line: 2, column: 12))
        #expect(error.message.contains("Negative values are not allowed"))
    }

    @Test func malformedStatementsAreLocatedErrors() throws {
        let cases: [(String, Int, Int)] = [
            ("pie\n  Dogs : 4", 2, 3),
            ("pie\n  \"Dogs\" 4", 2, 9),
            ("pie\n  \"Dogs\" : many", 2, 12),
            ("pie\n  \"Dogs : 4", 2, 3),
        ]
        for (source, line, column) in cases {
            let error = try #require(throws: MermaidError.self) { try parse(source) }
            #expect(error.kind == MermaidError.Kind.syntax, "\(source)")
            #expect(error.location == SourceLocation(line: line, column: column), "\(source)")
        }
    }
}
