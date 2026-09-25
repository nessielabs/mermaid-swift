extension Theme {
    public static let defaultFontFamily = "\"trebuchet ms\", verdana, arial, sans-serif"

    public static let `default` = Theme(.default)
    public static let neutral = Theme(.neutral)
    public static let dark = Theme(.dark)
    public static let forest = Theme(.forest)

    /// Builds a named theme, applying `variables` (Mermaid `themeVariables`)
    /// before deriving every variable that was not set explicitly, which is
    /// how mermaid.js resolves themes: overriding `primaryColor` in the
    /// `base` theme recolors everything derived from it.
    public init(_ name: Name, variables: [String: String] = [:]) {
        let preset = Self.presets[name] ?? [:]
        var explicit: [String: Color] = [:]
        for (key, value) in preset.merging(variables, uniquingKeysWith: { _, override in override }) {
            if let color = Color(css: value) { explicit[key] = color }
        }
        let dark = explicit["background"].map { $0.isDark } ?? (name == .dark)
        func v(_ key: String, _ derive: @autoclosure () -> Color) -> Color {
            if let color = explicit[key] { return color }
            let color = derive()
            explicit[key] = color
            return color
        }
        func border(_ color: Color) -> Color {
            dark ? color.adjusted(saturation: -40, lightness: 10) : color.adjusted(saturation: -40, lightness: -10)
        }

        let background = v("background", .white)
        let primary = v("primaryColor", Color(hex: 0xFFF4DD))
        let secondary = v("secondaryColor", primary.adjusted(hue: -120))
        let tertiary = v("tertiaryColor", primary.adjusted(hue: 180, lightness: 5))
        let text = v("textColor", background.inverted)
        let mainBkg = v("mainBkg", primary)

        self.name = name
        fontFamily = variables["fontFamily"] ?? Self.defaultFontFamily
        fontSize = variables["fontSize"].flatMap { ElementStyle.length($0) } ?? 16
        self.background = background
        primaryColor = primary
        primaryBorderColor = v("primaryBorderColor", border(primary))
        primaryTextColor = v("primaryTextColor", primary.inverted)
        secondaryColor = secondary
        secondaryBorderColor = v("secondaryBorderColor", border(secondary))
        secondaryTextColor = v("secondaryTextColor", secondary.inverted)
        tertiaryColor = tertiary
        tertiaryBorderColor = v("tertiaryBorderColor", border(tertiary))
        tertiaryTextColor = v("tertiaryTextColor", tertiary.inverted)
        textColor = text
        lineColor = v("lineColor", background.inverted)
        self.mainBkg = mainBkg
        nodeBorder = v("nodeBorder", border(primary))
        nodeTextColor = v("nodeTextColor", v("primaryTextColor", primary.inverted))
        clusterBkg = v("clusterBkg", tertiary)
        clusterBorder = v("clusterBorder", border(tertiary))
        titleColor = v("titleColor", text)
        edgeLabelBackground = v("edgeLabelBackground", dark ? secondary.darkened(30) : secondary.lightened(10))
        noteBkgColor = v("noteBkgColor", Color(hex: 0xFFF5AD))
        noteBorderColor = v("noteBorderColor", border(Color(hex: 0xFFF5AD)))
        noteTextColor = v("noteTextColor", Color(hex: 0x333333))

        let hues: [Double] = [0, 0, 0, 30, 60, 90, 120, 150, 210, 270, 300, 330]
        sectionColors = hues.enumerated().map { i, hue in
            if let fixed = Self.fixedSectionColors[name]?[i].flatMap({ Color(css: $0) }) {
                return v("cScale\(i)", fixed)
            }
            // The base theme lifts cScale8's lightness by 150 points (to white).
            let lift: Double = name == .base && i == 8 ? 150 : 0
            let base = i == 1 ? secondary : (i == 2 ? tertiary : primary.adjusted(hue: hue, lightness: lift))
            switch name {
            case .default, .forest: return v("cScale\(i)", base.darkened(10))
            case .base: return v("cScale\(i)", base.darkened(dark ? 75 : 25))
            case .dark, .neutral: return v("cScale\(i)", base)
            }
        }
        // Each mermaid.js theme derives its pie palette differently: the
        // dark and neutral themes reuse the section scale (pie12 wraps to
        // cScale0), the others adjust hue and lightness.
        let pieSpec: [(Color, Double, Double)]
        switch name {
        case .default:
            pieSpec = [
                (primary, 0, 0), (secondary, 0, 0), (tertiary, 0, -40),
                (primary, 0, -10), (secondary, 0, -30), (tertiary, 0, -20),
                (primary, 60, -20), (primary, -60, -40), (primary, 120, -40),
                (primary, 60, -40), (primary, -90, -40), (primary, 120, -30),
            ]
        case .forest:
            pieSpec = [
                (primary, 0, 0), (secondary, 0, 0), (tertiary, 0, 0),
                (primary, 0, -30), (secondary, 0, -30), (tertiary, 40, -40),
                (primary, 60, -10), (primary, -60, -10), (primary, 120, 0),
                (primary, 60, -50), (primary, -60, -50), (primary, 120, -50),
            ]
        case .dark, .neutral:
            let sections = sectionColors
            pieSpec = (1...12).map { (sections[$0 % sections.count], 0, 0) }
        case .base:
            pieSpec = [
                (primary, 0, 0), (secondary, 0, 0), (tertiary, 0, 0),
                (primary, 0, -10), (secondary, 0, -10), (tertiary, 0, -10),
                (primary, 60, -10), (primary, -60, -10), (primary, 120, 0),
                (primary, 60, -20), (primary, -60, -20), (primary, 120, -10),
            ]
        }
        pieColors = pieSpec.enumerated().map { i, spec in
            v("pie\(i + 1)", spec.0.adjusted(hue: spec.1, lightness: spec.2))
        }
        let modeled: Set<String> = [
            "background", "primaryColor", "primaryBorderColor", "primaryTextColor", "secondaryColor",
            "secondaryBorderColor", "secondaryTextColor", "tertiaryColor", "tertiaryBorderColor",
            "tertiaryTextColor", "textColor", "lineColor", "mainBkg", "nodeBorder", "nodeTextColor",
            "clusterBkg", "clusterBorder", "titleColor", "edgeLabelBackground", "noteBkgColor",
            "noteBorderColor", "noteTextColor",
        ]
        extras = explicit.filter { key, _ in
            !modeled.contains(key) && !(key.hasPrefix("cScale") && Int(key.dropFirst(6)) != nil) && !(key.hasPrefix("pie") && Int(key.dropFirst(3)) != nil)
        }
    }

    /// Section scale colors (`cScale0`...`cScale11`) that mermaid.js' dark
    /// and neutral themes define outright; nil entries are derived.
    static let fixedSectionColors: [Name: [String?]] = [
        .dark: [nil, "#0b0000", "#4d1037", "#3f5258", "#4f2f1b", "#6e0a0a", "#3b0048", "#995a01", "#154706",
                "#161722", "#00296f", "#01629c"],
        .neutral: ["#555", "#F4F4F4", "#555", "#BBB", "#777", "#999", "#DDD", "#FFF", "#DDD", "#BBB", "#999", "#777"],
    ]

    /// Base variables for each named theme, from mermaid.js' theme files.
    /// Everything else is derived.
    static let presets: [Name: [String: String]] = [
        .default: [
            "primaryColor": "#ECECFF", "secondaryColor": "#ffffde", "tertiaryColor": "hsl(80, 100%, 96.27%)",
            "primaryTextColor": "#131300", "lineColor": "#333333", "textColor": "#333333",
            "mainBkg": "#ECECFF", "nodeBorder": "#9370DB", "clusterBkg": "#ffffde", "clusterBorder": "#aaaa33",
            "titleColor": "#333333", "edgeLabelBackground": "#e8e8e8", "noteBorderColor": "#aaaa33",
            "actorBkg": "#ECECFF", "actorBorder": "hsl(259.63, 59.78%, 87.9%)", "activationBkgColor": "#f4f4f4",
        ],
        .neutral: [
            "primaryColor": "#eeeeee", "secondaryColor": "#f4f4f4", "tertiaryColor": "#fafafa",
            "primaryTextColor": "#111111", "lineColor": "#666666", "textColor": "#333333",
            "mainBkg": "#eeeeee", "nodeBorder": "#999999", "clusterBkg": "#fafafa", "clusterBorder": "#707070",
            "titleColor": "#333333", "edgeLabelBackground": "#ffffff", "noteBorderColor": "#999999",
            "cScale0": "#555", "cScale1": "#F4F4F4", "cScale2": "#555", "cScale3": "#BBB", "cScale4": "#777",
            "cScale5": "#999", "cScale6": "#DDD", "cScale7": "#FFF", "cScale8": "#DDD", "cScale9": "#BBB",
            "cScale10": "#999", "cScale11": "#777",
        ],
        .dark: [
            "background": "#333333", "primaryColor": "#1f2020", "secondaryColor": "#474949",
            "tertiaryColor": "#20201f", "primaryTextColor": "#e0dfdf", "lineColor": "#cccccc",
            "textColor": "#cccccc", "mainBkg": "#1f2020", "nodeBorder": "#cccccc", "clusterBkg": "#474949",
            "clusterBorder": "rgba(255, 255, 255, 0.25)", "titleColor": "#F9FFFE", "edgeLabelBackground": "#585858",
            "noteBkgColor": "#474949", "noteTextColor": "#e0dfdf", "noteBorderColor": "#cccccc",
            // mermaid.js hard-codes the dark section scale after cScale0.
            "cScale1": "#0b0000", "cScale2": "#4d1037", "cScale3": "#3f5258", "cScale4": "#4f2f1b",
            "cScale5": "#6e0a0a", "cScale6": "#3b0048", "cScale7": "#995a01", "cScale8": "#154706",
            "cScale9": "#161722", "cScale10": "#00296f", "cScale11": "#01629c",
        ],
        .forest: [
            "primaryColor": "#cde498", "secondaryColor": "#cdffb2", "tertiaryColor": "#f4f4f4",
            "primaryTextColor": "#000000", "lineColor": "#008000", "textColor": "#000000",
            "mainBkg": "#cde498", "nodeBorder": "#13540c", "clusterBkg": "#cdffb2", "clusterBorder": "#6eaa49",
            "titleColor": "#333333", "edgeLabelBackground": "#e8e8e8", "noteBorderColor": "#6eaa49",
        ],
        .base: [:],
    ]
}

extension Theme {
    /// Resolves the theme selected by Mermaid configuration: the `theme`
    /// name (or `fallback`) plus any `themeVariables`, `fontFamily`, and
    /// `fontSize`.
    public init(config: ConfigValue, fallback: Name = .default) {
        var variables: [String: String] = [:]
        for (key, value) in config["themeVariables"]?.objectValue ?? [:] {
            if let text = value.stringValue { variables[key] = text }
        }
        let name = config["theme"]?.stringValue.flatMap { Name(rawValue: $0.lowercased()) } ?? fallback
        self.init(name, variables: variables)
        if let family = config["fontFamily"]?.stringValue { fontFamily = family }
        if let size = config["fontSize"]?.numberValue { fontSize = size }
    }
}
