import Testing
@testable import Mermaid

@Suite("Themes")
struct ThemeTests {
    @Test func defaultThemeMatchesMermaid() {
        let theme = Theme.default
        #expect(theme.mainBkg == Color(css: "#ECECFF"))
        #expect(theme.nodeBorder == Color(css: "#9370DB"))
        #expect(theme.lineColor == Color(css: "#333333"))
        #expect(theme.color("actorBkg") == Color(css: "#ECECFF"))
        #expect(theme.sectionColors.count == 12)
        #expect(theme.pieColors.count == 12)
    }

    @Test func baseThemeDerivesFromOverriddenPrimary() {
        let theme = Theme(.base, variables: ["primaryColor": "#BB2528"])
        #expect(theme.primaryColor == Color(css: "#BB2528"))
        #expect(theme.mainBkg == theme.primaryColor)
        #expect(theme.primaryBorderColor.hsl.lightness < theme.primaryColor.hsl.lightness)
        #expect(theme.pieColors[0] == theme.primaryColor)
    }

    @Test func explicitVariablesWinOverDerivation() {
        let theme = Theme(.base, variables: ["primaryColor": "#ff0000", "mainBkg": "#00ff00", "git0": "#123456"])
        #expect(theme.mainBkg == Color(css: "#00ff00"))
        #expect(theme.color("git0") == Color(css: "#123456"))
    }

    @Test func sectionScaleFollowsEachTheme() {
        // default and forest darken the derived scale by 10 points.
        #expect(Theme.default.sectionColors[0] == Color(css: "#ECECFF")!.darkened(10))
        #expect(Theme.forest.sectionColors[1] == Color(css: "#cdffb2")!.darkened(10))
        // dark and neutral define most of the scale outright.
        #expect(Theme.dark.sectionColors[0] == Theme.dark.primaryColor)
        #expect(Theme.dark.sectionColors[1] == Color(css: "#0b0000"))
        #expect(Theme.neutral.sectionColors[0] == Color(css: "#555"))
        // base darkens by 25; explicit values are kept as given.
        #expect(Theme(.base).sectionColors[0] == Theme(.base).primaryColor.darkened(25))
        let custom = Theme(.default, variables: ["cScale0": "#ff0000", "cScaleLabel0": "#ffffff"])
        #expect(custom.sectionColors[0] == Color(css: "#ff0000"))
        #expect(custom.color("cScaleLabel0") == Color(css: "#ffffff"))
    }

    @Test func sectionScaleHelpersRepeatAndStayLegible() {
        let theme = Theme.default
        #expect(theme.scaleColor(12) == theme.scaleColor(0) && theme.scaleColor(-1) == theme.scaleColor(11))
        #expect(theme.scaleLabelColor(0) == .black)
        #expect(Theme.dark.scaleLabelColor(1) == Color(hex: 0xD3D3D3))
        #expect(Theme.neutral.scaleLabelColor(0) == Color(css: "#F4F4F4"))
        // Neutral's white slot would make light labels invisible.
        #expect(Theme.neutral.scaleLabelColor(7) == Color(hex: 0x333333))
        let custom = Theme(.default, variables: ["cScale0": "#000000"])
        #expect(custom.scaleLabelColor(0) == .white)
        #expect(Theme(.default, variables: ["cScaleLabel2": "#123456"]).scaleLabelColor(14) == Color(hex: 0x123456))
        #expect(Theme.neutral.scaleInverseColor(7) == .black)
    }

    @Test func piePalettesFollowEachTheme() {
        let theme = Theme.default
        #expect(theme.pieColors[1] == theme.secondaryColor)
        #expect(theme.pieColors[2] == theme.tertiaryColor.adjusted(lightness: -40))
        #expect(theme.pieColors[7] == theme.primaryColor.adjusted(hue: -60, lightness: -40))
        #expect(Theme.dark.pieColors[0] == Theme.dark.sectionColors[1])
        #expect(Theme.dark.sectionColors[2] == Color(css: "#4d1037"))
        #expect(Theme.neutral.pieColors[11] == Theme.neutral.sectionColors[0])
        #expect(Theme(.default, variables: ["pie3": "#123456"]).pieColors[2] == Color(css: "#123456"))
    }

    @Test func darkThemeUsesLightLines() {
        #expect(Theme.dark.background.isDark)
        #expect(!Theme.dark.lineColor.isDark)
    }

    @Test func configSelectsThemeAndFont() throws {
        let config = try LenientJSON.parse(
            "{theme: 'forest', fontSize: '14px', themeVariables: {primaryColor: '#abcdef'}}")
        let theme = Theme(config: config)
        #expect(theme.name == .forest)
        #expect(theme.fontSize == 14)
        #expect(theme.primaryColor == Color(css: "#abcdef"))
    }
}
