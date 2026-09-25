/// The git graph theme variables (`git0`...`git7`, `gitInv0`...,
/// `gitBranchLabel0`..., and the commit and tag label colors), derived the
/// way each mermaid.js theme derives them unless set in `themeVariables`.
struct GitGraphPalette {
    static let count = 8

    var branch: [Color]
    var highlight: [Color]
    var branchLabel: [Color]
    var commitLabel: Color
    var commitLabelBackground: Color
    var tagLabel: Color
    var tagLabelBackground: Color
    var tagLabelBorder: Color
    /// Fill of a merge commit's inner dot and a highlight's inner square.
    var commitInner: Color
    var branchLine: Color
    var tagHole: Color

    init(theme: Theme) {
        let t = theme
        let dark = t.background.isDark
        let derived: [Color]
        switch t.name {
        case .dark:
            // theme-dark.js ignores explicit gitN values and lightens the pie
            // colors, which are its section scale.
            let scale = t.sectionColors
            func pie(_ i: Int) -> Color { scale.indices.contains(i) ? scale[i] : t.primaryColor }
            derived = [t.secondaryColor.lightened(20)] + (1..<Self.count).map { i in
                pie(i + 1).lightened(i == 5 || i == 6 ? 10 : 20)
            }
        case .neutral:
            let pies = t.pieColors
            derived = (0..<Self.count).map { i in
                let base = pies.indices.contains(i) ? pies[i] : t.primaryColor
                return i == 0 ? base.darkened(25) : base
            }
        default:
            let p = t.primaryColor
            let bases = [p, t.secondaryColor, t.tertiaryColor, p.adjusted(hue: -30), p.adjusted(hue: -60),
                         p.adjusted(hue: -90), p.adjusted(hue: 60), p.adjusted(hue: 120)]
            // Like mermaid.js, explicit values are darkened (or lightened) too.
            derived = bases.enumerated().map { i, base in
                let color = t.color("git\(i)") ?? base
                return dark ? color.lightened(25) : color.darkened(25)
            }
        }
        branch = derived
        highlight = derived.enumerated().map { i, color in
            t.color("gitInv\(i)") ?? (i == 0 && t.name == .default ? color.inverted.darkened(25) : color.inverted)
        }
        branchLabel = derived.enumerated().map { i, color in
            t.color("gitBranchLabel\(i)") ?? (color.luminance > 0.33 ? .black : .white)
        }
        commitLabel = t.color("commitLabelColor") ?? t.secondaryTextColor
        commitLabelBackground = t.color("commitLabelBackground") ?? t.secondaryColor
        tagLabel = t.color("tagLabelColor") ?? t.primaryTextColor
        tagLabelBackground = t.color("tagLabelBackground") ?? t.primaryColor
        tagLabelBorder = t.color("tagBorder") ?? t.color("tagLabelBorder") ?? t.primaryBorderColor
        commitInner = t.primaryColor
        branchLine = t.color("commitLineColor") ?? t.lineColor
        tagHole = t.textColor
    }

    func branchColor(_ index: Int) -> Color { branch[index % Self.count] }
    func highlightColor(_ index: Int) -> Color { highlight[index % Self.count] }
    func labelColor(_ index: Int) -> Color { branchLabel[index % Self.count] }
}
