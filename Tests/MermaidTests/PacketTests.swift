import Testing
@testable import Mermaid

@Suite("Packet diagrams")
struct PacketTests {
    func parse(_ source: String) throws -> PacketDiagram {
        try #require(try Mermaid.parse(source).diagram as? PacketDiagram)
    }

    func expectError(_ source: String, line: Int, column: Int? = nil, containing text: String? = nil,
                     sourceLocation: Testing.SourceLocation = #_sourceLocation) {
        do {
            _ = try parse(source)
            Issue.record("expected an error", sourceLocation: sourceLocation)
        } catch let error as MermaidError {
            #expect(error.location?.line == line, "\(error)", sourceLocation: sourceLocation)
            if let column { #expect(error.location?.column == column, "\(error)", sourceLocation: sourceLocation) }
            if let text { #expect(error.message.contains(text), "\(error)", sourceLocation: sourceLocation) }
        } catch {
            Issue.record("unexpected \(error)", sourceLocation: sourceLocation)
        }
    }

    @Test func parsesRangesSingleBitsAndCounts() throws {
        let d = try parse("""
        packet-beta
          title UDP Packet
          0-15: "Source Port"
          +16: 'Destination Port' %% trailing comment
          32: "Flag"
          +7: "Rest"
        """)
        #expect(d.title == "UDP Packet")
        #expect(d.fields.map { [$0.start, $0.end] } == [[0, 15], [16, 31], [32, 32], [33, 39]])
        #expect(d.fields[1].label == "Destination Port")
        #expect(d.bitCount == 40)
    }

    @Test func mermaidValidationErrorsAreLocated() {
        expectError("packet\n0-15: \"a\"\n17-20: \"b\"", line: 3, column: 1, containing: "not contiguous. It should start from 16")
        expectError("packet\n0-15: \"a\"\n16-10: \"b\"", line: 3, column: 4, containing: "End must be greater than start")
        expectError("packet\n+0: \"a\"", line: 2, column: 2, containing: "zero bit field")
        expectError("packet\n0-3 \"a\"", line: 2, column: 5, containing: "':'")
        expectError("packet\n0-3: a", line: 2, column: 6, containing: "quoted")
        expectError("packet\n0-3: \"a", line: 2, column: 6, containing: "closing")
        expectError("packet\nfoo", line: 2, column: 1)
    }

    @Test func splitsFieldsAtRowBoundaries() throws {
        let d = try parse("packet\n0-9: \"a\"\n10-40: \"b\"")
        let rows = d.rows(bitsPerRow: 16)
        #expect(rows.count == 3)
        #expect(rows[0].map { [$0.start, $0.end] } == [[0, 9], [10, 15]])
        #expect(rows[1].map { [$0.start, $0.end] } == [[16, 31]])
        #expect(rows[2].map { [$0.start, $0.end] } == [[32, 40]])
        #expect(rows.flatMap { $0 }.allSatisfy { $0.start / 16 == $0.end / 16 })
    }

    @Test func runawayRangesAreCapped() throws {
        let d = try parse("packet\n0-99999999: \"huge\"")
        #expect(d.rows(bitsPerRow: 32).count == PacketDiagram.maximumRows)
    }

    /// Every bit of every row is covered exactly once, in both bit orders.
    @Test(arguments: [false, true]) func segmentsCoverEveryBitOnce(descending: Bool) throws {
        let d = try parse("packet\n0-4: \"a\"\n+11: \"b\"\n16: \"c\"\n17-47: \"d\"\n+3: \"e\"")
        var config = ConfigValue.object(["bitsPerRow": .number(16)])
        if descending { config = config.merging(.object(["bitOrder": .string("descending")])) }
        let settings = PacketSceneBuilder.Settings(config)
        for row in d.rows(bitsPerRow: 16) {
            var columns = Set<Int>()
            for segment in row {
                let frame = PacketSceneBuilder.frame(of: segment, rowY: 0, settings: settings)
                let first = Int(((frame.minX - 1) / settings.bitWidth).rounded())
                for c in first..<(first + segment.bitCount) {
                    #expect(c >= 0 && c < 16)
                    #expect(columns.insert(c).inserted, "bit column \(c) covered twice")
                }
            }
            #expect(columns.count == row.reduce(0) { $0 + $1.bitCount })
        }
    }

    @Test func descendingOrderMirrorsRows() {
        var config = ConfigValue.object(["bitsPerRow": .number(8), "bitOrder": .string("descending")])
        var settings = PacketSceneBuilder.Settings(config)
        let low = PacketDiagram.Segment(start: 0, end: 1, label: "", field: 0)
        #expect(PacketSceneBuilder.frame(of: low, rowY: 0, settings: settings).minX == 6 * settings.bitWidth + 1)
        config = .object(["bitsPerRow": .number(8)])
        settings = PacketSceneBuilder.Settings(config)
        #expect(PacketSceneBuilder.frame(of: low, rowY: 0, settings: settings).minX == 1)
    }

    @Test func rendersRowsLabelsAndBitNumbers() throws {
        let scene = try Mermaid.render("packet\n0-15: \"Source Port\"\n16-31: \"Dest\"\n32-39: \"X\"",
                                       options: RenderOptions(measurer: ApproximateTextMeasurer()))
        let svg = scene.svg
        #expect(svg.contains(">Source Port</text>") && svg.contains(">31</text>") && svg.contains(">39</text>"))
        #expect(svg.components(separatedBy: "class=\"packet-row\"").count - 1 == 2)
        // 32 bits of 32 px, plus the canvas margin.
        #expect(scene.size.width == 32 * 32 + 2 + 16)
        let hidden = try Mermaid.render("---\nconfig:\n  packet:\n    showBits: false\n---\npacket\n0-3: \"a\"",
                                        options: RenderOptions(measurer: ApproximateTextMeasurer()))
        #expect(!hidden.svg.contains(">3</text>"))
    }
}
