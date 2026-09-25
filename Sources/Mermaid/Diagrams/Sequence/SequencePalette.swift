/// The colors a sequence diagram is drawn with, from the theme's
/// sequence variables. Variables a theme does not set are derived from
/// its base colors the way mermaid.js' base theme derives them.
struct SequencePalette {
    var actorBkg: Color
    var actorBorder: Color
    var actorTextColor: Color
    var actorLineColor: Color
    /// The stroke of participant glyphs, which are thin lines and need more
    /// contrast than the box border they would otherwise share.
    var glyphColor: Color
    var signalColor: Color
    var signalTextColor: Color
    var labelBoxBkgColor: Color
    var labelBoxBorderColor: Color
    var labelTextColor: Color
    var loopTextColor: Color
    var noteBkgColor: Color
    var noteBorderColor: Color
    var noteTextColor: Color
    var activationBkgColor: Color
    var activationBorderColor: Color
    var sequenceNumberColor: Color
    /// The fill of a `rect` without a valid color.
    var rectBkgColor: Color
    var background: Color
    var groupBorder: Color
    var groupTextColor: Color

    init(theme: Theme) {
        func v(_ name: String, _ fallback: Color) -> Color { theme.color(name, default: fallback) }
        actorBkg = v("actorBkg", theme.mainBkg)
        actorBorder = v("actorBorder", theme.primaryBorderColor)
        actorTextColor = v("actorTextColor", theme.primaryTextColor)
        actorLineColor = v("actorLineColor", actorBorder.isClear ? theme.lineColor : actorBorder.mixed(with: theme.lineColor, amount: 0.35))
        glyphColor = actorBorder.mixed(with: actorTextColor, amount: 0.45)
        signalColor = v("signalColor", theme.textColor)
        signalTextColor = v("signalTextColor", theme.textColor)
        labelBoxBkgColor = v("labelBoxBkgColor", actorBkg)
        labelBoxBorderColor = v("labelBoxBorderColor", actorBorder)
        labelTextColor = v("labelTextColor", actorTextColor)
        loopTextColor = v("loopTextColor", actorTextColor)
        noteBkgColor = theme.noteBkgColor
        noteBorderColor = theme.noteBorderColor
        noteTextColor = theme.noteTextColor
        activationBkgColor = v("activationBkgColor", theme.secondaryColor)
        activationBorderColor = v("activationBorderColor", theme.lineColor.mixed(with: theme.background, amount: 0.3))
        sequenceNumberColor = v("sequenceNumberColor", signalColor.isDark ? .white : .black)
        rectBkgColor = v("rectBkgColor", actorBkg.withAlpha(0.5))
        background = theme.background
        groupBorder = theme.lineColor.withAlpha(0.5)
        groupTextColor = theme.textColor
    }
}
