import Testing
@testable import Mermaid

@Suite("XY chart layout")
struct XYChartLayoutTests {
    let context = RenderContext(measurer: ApproximateTextMeasurer())

    func builder(_ body: String, header: String = "xychart", config: ConfigValue = .object([:])) throws -> XYChartSceneBuilder {
        let prepared = try Preprocessor.prepare(header + "\n" + body)
        let diagram = try XYChartParser.parse(DiagramSource(prepared: prepared, header: prepared.header!))
        let ctx = RenderContext(theme: Theme(config: config), measurer: ApproximateTextMeasurer(), config: config)
        return XYChartSceneBuilder(diagram: diagram, context: ctx)
    }

    func groups(_ items: [SceneItem], role: String) -> [GroupItem] {
        items.flatMap { item -> [GroupItem] in
            guard case .group(let group) = item else { return [] }
            return (group.role == role ? [group] : []) + groups(group.items, role: role)
        }
    }

    func rects(_ group: GroupItem) -> [Rect] {
        group.items.compactMap { item in
            if case .shape(let shape) = item, shape.fill != nil { return shape.path.bounds } else { return nil }
        }
    }

    func texts(_ group: GroupItem) -> [TextItem] {
        group.items.compactMap { if case .text(let t) = $0 { return t } else { return nil } }
    }

    @Test func verticalLayoutFillsTheChart() throws {
        let b = try builder("title T\nx-axis X [a, b, c]\ny-axis Y 0 --> 10\nbar [1, 5, 10]")
        let layout = b.layout()
        #expect(layout.plot.minX > 0 && layout.plot.minY > 0)
        #expect(abs(layout.plot.maxX - 700) < 1e-9)
        #expect(abs(layout.plot.maxY + layout.xAxis.bounds.height - 500) < 1e-9)
        #expect(layout.yAxis.bounds.maxX == layout.plot.minX)
        #expect(layout.xAxis.bounds.minY == layout.plot.maxY)
        #expect(layout.xAxis.showsTitle && layout.yAxis.showsTitle && layout.xAxis.showsLabels)
    }

    @Test func barsStandOnZeroAtTheirCategories() throws {
        let b = try builder("x-axis [a, b, c]\ny-axis -10 --> 10\nbar [5, -5, 10]")
        let layout = b.layout()
        let bars = rects(try #require(groups(b.plotItems(layout), role: "bar-plot").first))
        #expect(bars.count == 3)
        let zero = layout.yAxis.position(of: 0)
        #expect(abs(bars[0].maxY - zero) < 1e-9 && abs(bars[1].minY - zero) < 1e-9)
        #expect(abs(bars[2].minY - layout.yAxis.position(of: 10)) < 1e-9)
        for (i, bar) in bars.enumerated() {
            #expect(abs(bar.midX - layout.xAxis.position(of: Double(i))) < 1e-9)
            #expect(bar.minX >= layout.plot.minX && bar.maxX <= layout.plot.maxX)
        }
        // Bars never overlap their neighbours.
        #expect(bars[0].maxX < bars[1].minX && bars[1].maxX < bars[2].minX)
    }

    @Test func horizontalChartsSwapTheAxes() throws {
        let b = try builder("x-axis [a, b]\nbar [1, 2]", header: "xychart horizontal")
        let layout = b.layout()
        #expect(layout.xAxis.position == .left && layout.yAxis.position == .top)
        let bars = rects(try #require(groups(b.plotItems(layout), role: "bar-plot").first))
        #expect(abs(bars[0].minX - layout.yAxis.position(of: 0)) < 1e-9 && bars[1].width > bars[0].width)
        #expect(bars[0].midY < bars[1].midY)
        // Configuration picks the orientation when the header does not.
        let configured = try builder("bar [1]", config: .object(["xyChart": .object(["chartOrientation": .string("horizontal")])]))
        #expect(configured.orientation == .horizontal)
    }

    @Test func linearTicksAreNiceNumbers() throws {
        let b = try builder("y-axis 0 --> 198.2\nline [1, 2]")
        let labels = b.layout().yAxis.tickValues.map { b.layout().yAxis.tickLabel($0) }
        #expect(labels == ["0", "20", "40", "60", "80", "100", "120", "140", "160", "180"])
    }

    @Test func legendListsOnlyTitledSeries() throws {
        let b = try builder("line \"avg\" [1, 2]\nline [2, 3]\nbar \"p95\" [3, 4]")
        #expect(b.legendEntries.map(\.index) == [0, 2])
        let layout = b.layout()
        #expect(layout.legendSize.width > 0 && layout.legendOrigin.x == layout.plot.maxX)
        let legend = try #require(groups(b.build().items, role: "legend").first)
        #expect(texts(legend).count == 2)
        let hidden = try builder("line \"avg\" [1, 2]", config: .object(["xyChart": .object(["showLegend": .bool(false)])]))
        #expect(hidden.legendEntries.isEmpty && hidden.layout().legendSize == .zero)
    }

    @Test func dataLabelsShareOneSizeAndStayInThePlot() throws {
        for outside in [false, true] {
            let b = try builder("x-axis [a, b, c]\nbar [12, 2, 25]", config: .object(["xyChart": .object([
                "showDataLabel": .bool(true), "showDataLabelOutsideBar": .bool(outside)])]))
            let layout = b.layout()
            let plot = try #require(groups(b.plotItems(layout), role: "bar-plot").first)
            let labels = texts(plot)
            #expect(labels.count == 3)
            #expect(Set(labels.map { $0.block.lines[0].runs[0].font.size }).count == 1)
            for label in labels { #expect(layout.plot.insetBy(dx: -1, dy: -1).contains(label.frame.center)) }
        }
    }

    @Test func paletteCyclesAndThinMarksStayVisible() throws {
        let config = ConfigValue.object(["themeVariables": .object(["xyChart": .object(["plotColorPalette": .string("#ff0000, #00ff00")])])])
        let b = try builder("bar [1]\nbar [2]\nbar [3]", config: config)
        #expect(b.plotColor(0) == Color(hex: 0xFF0000) && b.plotColor(2) == Color(hex: 0xFF0000))
        let pale = try builder("line [1, 2]")
        #expect(pale.plotColor(0) == Color(css: "#ECECFF"))
        let stroke = pale.strokeColor(0)
        #expect((Color.white.luminance + 0.05) / (stroke.luminance + 0.05) >= 2)
    }

    @Test func everythingFitsTheScene() throws {
        for header in ["xychart", "xychart horizontal"] {
            let source = "\(header)\n title \"A title\"\n x-axis \"Categories\" [alpha, beta, \"gamma delta\"]\n y-axis Values\n bar \"b\" [3, -2, 7]\n line \"l\" [1 \"low\", 5, 2 \"x\"]"
            let scene = try Mermaid.render(source, options: RenderOptions(measurer: ApproximateTextMeasurer()))
            for item in scene.items {
                guard let box = item.bounds else { continue }
                #expect(box.minX >= -0.5 && box.minY >= -0.5 && box.maxX <= scene.size.width + 0.5 && box.maxY <= scene.size.height + 0.5)
            }
        }
    }

    @Test func rotatedBottomLabelsReserveTheirHeight() throws {
        let flat = try builder("x-axis [\"a long category\", b]\nbar [1, 2]")
        let rotated = try builder("x-axis [\"a long category\", b]\nbar [1, 2]",
                                  config: .object(["xyChart": .object(["xAxis": .object(["labelRotation": .number(45)])])]))
        #expect(rotated.layout().xAxis.bounds.height > flat.layout().xAxis.bounds.height)
    }
}
