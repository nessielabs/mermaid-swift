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
