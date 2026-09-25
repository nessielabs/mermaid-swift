extension PacketDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        PacketSceneBuilder(diagram: self, context: context).build()
    }
}

/// Lays out packet rows the way mermaid.js does: every bit is `bitWidth`
/// wide, rows are `rowHeight` tall, and bit numbers sit above each field.
struct PacketSceneBuilder {
    let diagram: PacketDiagram
    let context: RenderContext

    /// Settings from `config.packet`, with mermaid.js defaults.
    struct Settings {
        var rowHeight = 32.0
        var bitWidth = 32.0
        var bitsPerRow = 32
        var showBits = true
        var descending = false
        var paddingX = 5.0
        var paddingY = 5.0

        init(_ config: ConfigValue) {
            rowHeight = max(1, config["rowHeight"]?.numberValue ?? rowHeight)
            bitWidth = max(1, config["bitWidth"]?.numberValue ?? bitWidth)
            bitsPerRow = max(1, Int(config["bitsPerRow"]?.numberValue ?? Double(bitsPerRow)))
            showBits = config["showBits"]?.boolValue ?? showBits
            descending = config["bitOrder"]?.stringValue?.lowercased() == "descending"
            paddingX = max(0, config["paddingX"]?.numberValue ?? paddingX)
            paddingY = max(0, config["paddingY"]?.numberValue ?? paddingY)
            // mermaid.js reserves room for the bit numbers above each row.
            if showBits { paddingY += 10 }
        }
    }

    /// Colors and font sizes from `themeVariables.packet`, which mermaid.js
    /// documents with fixed light defaults. On a dark theme the defaults
    /// follow the theme instead so the diagram stays legible.
    struct Style {
        var byteFontSize = 10.0
        var startByteColor: Color
        var endByteColor: Color
        var labelColor: Color
        var labelFontSize = 12.0
        var blockStrokeColor: Color
        var blockStrokeWidth = 1.0
        var blockFillColor: Color

        init(theme: Theme, variables: ConfigValue?) {
            let dark = theme.background.isDark
            let text = dark ? theme.textColor : .black
            startByteColor = text
            endByteColor = text
            labelColor = dark ? theme.primaryTextColor : .black
            blockStrokeColor = dark ? theme.lineColor : .black
            blockFillColor = dark ? theme.mainBkg : Color(hex: 0xEFEFEF)
            guard let v = variables else { return }
            func color(_ key: String) -> Color? { v[key]?.stringValue.flatMap { Color(css: $0) } }
            byteFontSize = v["byteFontSize"]?.numberValue ?? byteFontSize
            labelFontSize = v["labelFontSize"]?.numberValue ?? labelFontSize
            blockStrokeWidth = v["blockStrokeWidth"]?.numberValue ?? blockStrokeWidth
            startByteColor = color("startByteColor") ?? startByteColor
            endByteColor = color("endByteColor") ?? endByteColor
            labelColor = color("labelColor") ?? labelColor
            blockStrokeColor = color("blockStrokeColor") ?? blockStrokeColor
            blockFillColor = color("blockFillColor") ?? blockFillColor
        }
    }

    func build() -> Scene {
        let settings = Settings(context.section("packet"))
        let style = Style(theme: context.theme, variables: context.config["themeVariables"]?["packet"])
        let rows = diagram.rows(bitsPerRow: settings.bitsPerRow)
        var items: [SceneItem] = []
        for (index, row) in rows.enumerated() {
            let y = Double(index) * (settings.rowHeight + settings.paddingY) + settings.paddingY
            items.append(.group(GroupItem(id: "row-\(index)", role: "packet-row",
                                          items: row.flatMap { segmentItems($0, y: y, settings: settings, style: style) })))
        }
        let width = settings.bitWidth * Double(settings.bitsPerRow) + 2
        let height = Double(rows.count) * (settings.rowHeight + settings.paddingY)
        let margin = context.section("packet")["diagramPadding"]?.numberValue ?? 8
        let title = diagram.title ?? context.title
        return DiagramCanvas(context: context, margin: margin, title: title)
            .scene(content: items, size: Size(width, max(height, 0)))
    }

    /// The frame of a segment: its first column (mirrored in descending
    /// order), `bitWidth` per bit, less the gap between fields.
    static func frame(of segment: PacketDiagram.Segment, rowY: Double, settings: Settings) -> Rect {
        let bits = segment.bitCount
        let firstColumn = segment.start % settings.bitsPerRow
        let column = settings.descending ? settings.bitsPerRow - firstColumn - bits : firstColumn
        return Rect(x: Double(column) * settings.bitWidth + 1, y: rowY,
                    width: max(1, Double(bits) * settings.bitWidth - settings.paddingX), height: settings.rowHeight)
    }

    private func segmentItems(_ segment: PacketDiagram.Segment, y: Double, settings: Settings, style: Style) -> [SceneItem] {
        let frame = Self.frame(of: segment, rowY: y, settings: settings)
        var items: [SceneItem] = [
            .shape(ShapeItem(.rect(frame), fill: style.blockFillColor,
                             stroke: style.blockStrokeWidth > 0 ? Stroke(style.blockStrokeColor, width: style.blockStrokeWidth) : nil)),
        ]
        let fitting = TextFitting(measurer: context.measurer, font: context.font(size: style.labelFontSize),
                                  minimumSize: min(7, style.labelFontSize))
        if let label = fitting.fit(LabelParser.parse(segment.label), in: Size(frame.width - 4, frame.height - 2)) {
            items.append(.text(TextItem(label, centeredAt: frame.center, color: style.labelColor)))
        }
        if settings.showBits { items += bitNumbers(segment, frame: frame, settings: settings, style: style) }
        return [.group(GroupItem(id: "field-\(segment.field)-\(segment.start)", role: "packet-field", items: items))]
    }

    /// The first and last bit numbers above a segment; a one-bit field shows
    /// a single centered number.
    private func bitNumbers(_ segment: PacketDiagram.Segment, frame: Rect, settings: Settings, style: Style) -> [SceneItem] {
        let (leading, trailing) = settings.descending ? (segment.end, segment.start) : (segment.start, segment.end)
        let font = context.font(size: style.byteFontSize)
        func number(_ bit: Int) -> TextBlock { TextBlock(RichText(plain: String(bit)), font: font, measurer: context.measurer) }
        let numbers = number(leading)
        let baselineTop = frame.minY - 2 - numbers.height
        if segment.bitCount == 1 {
            return [.text(TextItem(numbers, frame: Rect(x: frame.minX, y: baselineTop, width: frame.width, height: numbers.height),
                                        alignment: .center, color: style.startByteColor))]
        }
        let last = number(trailing)
        return [
            .text(TextItem(numbers, frame: Rect(x: frame.minX, y: baselineTop, width: numbers.width, height: numbers.height),
                           alignment: .leading, color: style.startByteColor)),
            .text(TextItem(last, frame: Rect(x: frame.maxX - last.width, y: baselineTop, width: last.width, height: last.height),
                           alignment: .trailing, color: style.endByteColor)),
        ]
    }
}
