/// Colors, fonts, and spacing for C4 diagrams, resolved from the `c4`
/// configuration section with mermaid.js's key names and defaults.
///
/// C4 uses the fixed C4-model palette rather than theme colors. The only
/// theme-dependent colors are the neutral ones (relationship lines,
/// boundary borders, and their text), which follow the theme on dark
/// backgrounds so they stay visible.
struct C4Palette {
    let config: ConfigValue
    let theme: Theme
    let wrap: Bool

    init(context: RenderContext) {
        config = context.section("c4")
        theme = context.theme
        wrap = config["wrap"]?.boolValue ?? context.config["wrap"]?.boolValue ?? true
    }

    func number(_ key: String, _ fallback: Double) -> Double { config[key]?.numberValue ?? fallback }

    // MARK: Spacing

    var diagramMarginX: Double { number("diagramMarginX", 50) }
    var diagramMarginY: Double { number("diagramMarginY", 10) }
    var shapeMargin: Double { number("c4ShapeMargin", 50) }
    var shapePadding: Double { number("c4ShapePadding", 20) }
    var shapeWidth: Double { number("width", 216) }
    var shapeHeight: Double { number("height", 60) }
    var shapesPerRow: Int { max(1, Int(number("c4ShapeInRow", 4))) }
    var boundariesPerRow: Int { max(1, Int(number("c4BoundaryInRow", 2))) }

    // MARK: Colors

    /// Mermaid's `<type>_bg_color` and `<type>_border_color` defaults.
    static let defaults: [String: (background: UInt32, border: UInt32)] = [
        "person": (0x08427B, 0x073B6F), "external_person": (0x686868, 0x8A8A8A),
        "system": (0x1168BD, 0x3C7FC0), "external_system": (0x999999, 0x8A8A8A),
        "container": (0x438DD5, 0x3C7FC0), "external_container": (0xB3B3B3, 0xA6A6A6),
        "component": (0x85BBF0, 0x78A8D8), "external_component": (0xCCCCCC, 0xBFBFBF),
    ]

    func background(for type: String) -> Color {
        color("\(type)_bg_color") ?? Color(hex: Self.defaultPair(type).background)
    }

    func border(for type: String) -> Color {
        color("\(type)_border_color") ?? Color(hex: Self.defaultPair(type).border)
    }

    /// Database and queue forms share their base type's colors.
    private static func defaultPair(_ type: String) -> (background: UInt32, border: UInt32) {
        let base = type.replacingOccurrences(of: "_db", with: "").replacingOccurrences(of: "_queue", with: "")
        return defaults[base] ?? defaults["system"]!
    }

    private func color(_ key: String) -> Color? { config[key]?.stringValue.flatMap(Color.init(css:)) }

    /// Text on an element: mermaid.js uses white everywhere, which is hard
    /// to read on the light component and external palettes, so the text
    /// color is whichever of white or near-black contrasts more.
    static func text(on background: Color) -> Color {
        let white = 1.05 / (background.luminance + 0.05)
        let black = (background.luminance + 0.05) / 0.05
        return white >= black * 0.55 ? .white : Color(hex: 0x1A1A1A)
    }

    /// The neutral C4 gray (`#444444`), or the theme's line color when the
    /// background is dark.
    var neutralLine: Color { theme.background.isDark ? theme.lineColor : Color(hex: 0x444444) }
    var neutralText: Color { theme.background.isDark ? theme.textColor : Color(hex: 0x444444) }

    // MARK: Fonts

    /// The font for an element type (`personFontSize`, ...), a boundary
    /// (`boundary`), or a relationship (`message`), offset by `delta`.
    func font(_ type: String, delta: Double = 0, bold: Bool = false, italic: Bool = false) -> Font {
        let size = number("\(type)FontSize", type == "message" ? 12 : 14)
        let family = config["\(type)FontFamily"]?.stringValue ?? theme.fontFamily
        let weight = config["\(type)FontWeight"]?.stringValue
        return Font(family: family, size: size + delta, bold: bold || weight == "bold", italic: italic)
    }
}
