/// The gantt theme variables, resolved for one theme.
///
/// Every color honors a `themeVariables` override of the same mermaid
/// name; otherwise it takes the value mermaid.js' theme files give it,
/// deriving from the theme's base colors the way the `base` theme does.
struct GanttPalette {
    var sectionBkgColor: Color
    var altSectionBkgColor: Color
    var sectionBkgColor2: Color
    var excludeBkgColor: Color
    var taskBorderColor: Color
    var taskBkgColor: Color
    var taskTextColor: Color
    var taskTextDarkColor: Color
    var taskTextOutsideColor: Color
    var taskTextClickableColor: Color
    var activeTaskBorderColor: Color
    var activeTaskBkgColor: Color
    var gridColor: Color
    var doneTaskBkgColor: Color
    var doneTaskBorderColor: Color
    var critBorderColor: Color
    var critBkgColor: Color
    var todayLineColor: Color
    var vertLineColor: Color
    var titleColor: Color
    var textColor: Color

    init(theme: Theme) {
        let preset = Self.presets[theme.name] ?? [:]
        func color(_ name: String, _ derived: @autoclosure () -> Color) -> Color {
            theme.color(name) ?? preset[name].flatMap { Color(css: $0) } ?? derived()
        }
        let lightGrey = Color(hex: 0xD3D3D3)
        sectionBkgColor = color("sectionBkgColor", theme.tertiaryColor)
        altSectionBkgColor = color("altSectionBkgColor", .white)
        sectionBkgColor2 = color("sectionBkgColor2", theme.primaryColor)
        excludeBkgColor = color("excludeBkgColor", Color(hex: 0xEEEEEE))
        taskBorderColor = color("taskBorderColor", theme.primaryBorderColor)
        taskBkgColor = color("taskBkgColor", theme.primaryColor)
        taskTextColor = color("taskTextColor", theme.textColor)
        taskTextDarkColor = color("taskTextDarkColor", theme.textColor)
        taskTextOutsideColor = color("taskTextOutsideColor", theme.textColor)
        taskTextClickableColor = color("taskTextClickableColor", Color(hex: 0x003163))
        activeTaskBorderColor = color("activeTaskBorderColor", theme.primaryColor)
        activeTaskBkgColor = color("activeTaskBkgColor", theme.primaryColor.lightened(23))
        gridColor = color("gridColor", lightGrey)
        doneTaskBkgColor = color("doneTaskBkgColor", lightGrey)
        doneTaskBorderColor = color("doneTaskBorderColor", Color(hex: 0x808080))
        critBorderColor = color("critBorderColor", Color(hex: 0xFF8888))
        critBkgColor = color("critBkgColor", Color(hex: 0xFF0000))
        todayLineColor = color("todayLineColor", Color(hex: 0xFF0000))
        vertLineColor = color("vertLineColor", Color(hex: 0x000080))
        titleColor = theme.titleColor
        textColor = theme.textColor
    }

    /// Values from mermaid.js' theme files that are not derived from the
    /// theme's base colors.
    static let presets: [Theme.Name: [String: String]] = [
        .default: [
            "sectionBkgColor": "rgba(102, 102, 255, 0.49)", "altSectionBkgColor": "white",
            "sectionBkgColor2": "#fff400", "taskBorderColor": "#534fbc", "taskBkgColor": "#8a90dd",
            "taskTextColor": "white", "taskTextDarkColor": "black", "taskTextOutsideColor": "black",
            "activeTaskBorderColor": "#534fbc", "activeTaskBkgColor": "#bfc7ff", "vertLineColor": "navy",
        ],
        .forest: [
            "sectionBkgColor": "#6eaa49", "altSectionBkgColor": "white", "sectionBkgColor2": "#6eaa49",
            "taskBorderColor": "#13540c", "taskBkgColor": "#487e3a", "taskTextColor": "white",
            "taskTextDarkColor": "black", "taskTextOutsideColor": "black", "activeTaskBorderColor": "#13540c",
            "activeTaskBkgColor": "#cde498", "vertLineColor": "#00BFFF",
        ],
        .neutral: [
            "sectionBkgColor": "#bcbcbc", "altSectionBkgColor": "white", "sectionBkgColor2": "#bcbcbc",
            "taskBorderColor": "#565656", "taskBkgColor": "#707070", "taskTextColor": "white",
            "taskTextDarkColor": "#333333", "taskTextOutsideColor": "#333333", "activeTaskBorderColor": "#565656",
            "activeTaskBkgColor": "#eeeeee", "gridColor": "#e5e5e5", "doneTaskBkgColor": "#bbbbbb",
            "doneTaskBorderColor": "#666666", "critBkgColor": "#dd4422", "critBorderColor": "#b1361b",
            "todayLineColor": "#dd4422", "vertLineColor": "#dd4422",
        ],
        .dark: [
            "sectionBkgColor": "#b4ac76", "altSectionBkgColor": "#333333", "sectionBkgColor2": "#EAE8D9",
            "excludeBkgColor": "#a09657", "taskBorderColor": "#ffffff", "taskBkgColor": "#595c5c",
            "taskTextColor": "#e2dcd6", "taskTextDarkColor": "#2c2c2c", "taskTextOutsideColor": "lightgrey",
            "activeTaskBorderColor": "#ffffff", "activeTaskBkgColor": "#81B1DB", "gridColor": "lightgrey",
            "doneTaskBkgColor": "lightgrey", "critBorderColor": "#E83737", "critBkgColor": "#E83737",
            "todayLineColor": "#DB5757", "vertLineColor": "#00BFFF",
        ],
    ]
}
