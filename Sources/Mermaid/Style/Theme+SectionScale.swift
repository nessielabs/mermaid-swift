extension Theme {
    /// The section color `cScale<n>` for any section index, repeating
    /// every twelve sections as mermaid.js does.
    public func scaleColor(_ index: Int) -> Color {
        sectionColors[Self.scaleSlot(index)]
    }

    /// The text color for a section (`cScaleLabel<n>`).
    ///
    /// An explicit `cScaleLabel<n>` wins. Otherwise the theme's label
    /// color is used (light gray on the dark theme, near-white on the
    /// neutral theme's dark slots), falling back to black or white when
    /// that color would not be legible on the section color, since
    /// mermaid's own defaults can leave labels unreadable.
    public func scaleLabelColor(_ index: Int) -> Color {
        let slot = Self.scaleSlot(index)
        if let explicit = color("cScaleLabel\(slot)") { return explicit }
        let preferred: Color
        switch name {
        case .dark: preferred = Color(hex: 0xD3D3D3)
        case .neutral: preferred = slot == 0 || slot == 2 ? sectionColors[1] : Color(hex: 0x333333)
        case .base: preferred = primaryTextColor
        case .default, .forest: preferred = .black
        }
        let background = scaleColor(index)
        guard Self.contrast(preferred, background) < 3 else { return preferred }
        return Self.contrast(.black, background) >= Self.contrast(.white, background) ? .black : .white
    }

    /// The contrasting line color for a section (`cScaleInv<n>`): the hue
    /// opposite for default and forest, the inverted color otherwise.
    public func scaleInverseColor(_ index: Int) -> Color {
        let slot = Self.scaleSlot(index)
        if let explicit = color("cScaleInv\(slot)") { return explicit }
        switch name {
        case .default, .forest: return scaleColor(index).adjusted(hue: 180)
        default: return scaleColor(index).inverted
        }
    }

    static func scaleSlot(_ index: Int) -> Int { ((index % 12) + 12) % 12 }

    /// The WCAG contrast ratio between two colors.
    static func contrast(_ a: Color, _ b: Color) -> Double {
        let (hi, lo) = a.luminance > b.luminance ? (a.luminance, b.luminance) : (b.luminance, a.luminance)
        return (hi + 0.05) / (lo + 0.05)
    }
}
