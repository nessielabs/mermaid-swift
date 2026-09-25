import Testing
@testable import Mermaid

@Suite("Sankey parsing")
struct SankeyParserTests {
    func parse(_ source: String) throws -> SankeyDiagram {
        let prepared = try Preprocessor.prepare(source)
        return try SankeyParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
    }

    @Test func rowsNodesAndBlankLines() throws {
        let d = try parse("""
        sankey-beta

        %% source,target,value
        Electricity grid,Over generation / exports,104.453

        Electricity grid, Heating and cooling - homes ,113.726
        Bio-conversion,Electricity grid,27
        """)
        #expect(d.nodes == ["Electricity grid", "Over generation / exports", "Heating and cooling - homes", "Bio-conversion"])
        #expect(d.links.map(\.source) == [0, 0, 3])
        #expect(d.links.map(\.target) == [1, 2, 0])
        #expect(d.links.map(\.value) == [104.453, 113.726, 27])
        #expect(d.links[2].location == SourceLocation(line: 7, column: 1))
    }

    @Test func quotedFieldsWithCommasQuotesAndNewlines() throws {
        let d = try parse(#"sankey"# + "\n" + #"Pumped heat,"Heating and cooling, ""homes""",193.026"# + "\n"
                          + #""Multi"# + "\n" + #"line",Agricultural 'waste',1"#)
        #expect(d.nodes == ["Pumped heat", "Heating and cooling, \"homes\"", "Multi\nline", "Agricultural 'waste'"])
    }

    @Test func errorsAreLocated() throws {
        let cases: [(String, Int, Int, MermaidError.Kind)] = [
            ("sankey\nA,B", 2, 1, .syntax),
            ("sankey\nA,B,1,2", 2, 1, .syntax),
            ("sankey\nA,B,lots", 2, 5, .syntax),
            ("sankey\nA,B,-3", 2, 5, .semantic),
            ("sankey\n,B,3", 2, 1, .syntax),
            ("sankey\n\"A,B,3", 2, 1, .syntax),
            ("sankey\n\"A\"x,B,3", 2, 4, .syntax),
            ("sankey extra\nA,B,1", 1, 8, .syntax),
        ]
        for (source, line, column, kind) in cases {
            let error = try #require(throws: MermaidError.self) { try parse(source) }
            #expect(error.kind == kind, "\(source)")
            #expect(error.location == SourceLocation(line: line, column: column), "\(source): \(error)")
        }
    }

    @Test func cyclesAreRejectedAtTheClosingLink() throws {
        let error = try #require(throws: MermaidError.self) { try parse("sankey\nA,B,1\nB,C,1\nC,A,1") }
        #expect(error.kind == .semantic && error.location == SourceLocation(line: 4, column: 1))
        let loop = try #require(throws: MermaidError.self) { try parse("sankey\nA,A,1") }
        #expect(loop.message.contains("Circular link"))
        // Diamonds are not cycles.
        #expect(try parse("sankey\nA,B,1\nA,C,1\nB,D,1\nC,D,1").links.count == 4)
    }
}
