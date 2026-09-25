/// Sequence diagram settings from `config.sequence`, using mermaid.js key
/// names and defaults.
struct SequenceSettings {
    var actorMargin = 50.0
    var width = 150.0
    var height = 65.0
    var boxMargin = 10.0
    var boxTextMargin = 5.0
    var noteMargin = 10.0
    var activationWidth = 10.0
    var wrapPadding = 10.0
    var labelBoxWidth = 50.0
    var labelBoxHeight = 20.0
    var diagramMarginX = 50.0
    var diagramMarginY = 10.0
    var mirrorActors = true
    var wrap = false
    var rightAngles = false
    var showSequenceNumbers = false
    var hideUnusedParticipants = false
    var messageAlign = TextItem.Alignment.center
    var noteAlign = TextItem.Alignment.center
    var actorFont: Font
    var messageFont: Font
    var noteFont: Font

    init(context: RenderContext) {
        let config = context.section("sequence")
        func number(_ key: String, _ value: inout Double) { if let n = config[key]?.numberValue { value = n } }
        func flag(_ key: String, _ value: inout Bool) { if let b = config[key]?.boolValue { value = b } }
        number("actorMargin", &actorMargin)
        number("width", &width)
        number("height", &height)
        number("boxMargin", &boxMargin)
        number("boxTextMargin", &boxTextMargin)
        number("noteMargin", &noteMargin)
        number("activationWidth", &activationWidth)
        number("wrapPadding", &wrapPadding)
        number("labelBoxWidth", &labelBoxWidth)
        number("labelBoxHeight", &labelBoxHeight)
        number("diagramMarginX", &diagramMarginX)
        number("diagramMarginY", &diagramMarginY)
        flag("mirrorActors", &mirrorActors)
        flag("rightAngles", &rightAngles)
        flag("showSequenceNumbers", &showSequenceNumbers)
        flag("hideUnusedParticipants", &hideUnusedParticipants)
        // `%%{wrap}%%` and a top-level `wrap` apply to every diagram type.
        wrap = config["wrap"]?.boolValue ?? context.config["wrap"]?.boolValue ?? false
        messageAlign = Self.alignment(config["messageAlign"]?.stringValue) ?? .center
        noteAlign = Self.alignment(config["noteAlign"]?.stringValue) ?? .center

        func font(_ prefix: String, size: Double) -> Font {
            let family = config[prefix + "FontFamily"]?.stringValue ?? context.theme.fontFamily
            let weight = config[prefix + "FontWeight"]?.stringValue ?? "400"
            let bold = weight == "bold" || (Double(weight).map { $0 >= 600 } ?? false)
            return Font(family: family, size: config[prefix + "FontSize"]?.numberValue ?? size, bold: bold)
        }
        actorFont = font("actor", size: 14)
        messageFont = font("message", size: 16)
        noteFont = font("note", size: 14)
    }

    private static func alignment(_ name: String?) -> TextItem.Alignment? {
        switch name?.lowercased() {
        case "left", "start": return .leading
        case "right", "end": return .trailing
        case "center", "middle": return .center
        default: return nil
        }
    }
}
