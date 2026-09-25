import Foundation

/// An sRGB color with straight (non-premultiplied) alpha, components 0...1.
public struct Color: Hashable, Sendable, CustomStringConvertible {
    public var red: Double
    public var green: Double
    public var blue: Double
    public var alpha: Double

    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red.clamped(to: 0...1)
        self.green = green.clamped(to: 0...1)
        self.blue = blue.clamped(to: 0...1)
        self.alpha = alpha.clamped(to: 0...1)
    }

    /// Creates a color from a 24-bit `0xRRGGBB` value.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  alpha: alpha)
    }

    public static let black = Color(hex: 0x000000)
    public static let white = Color(hex: 0xFFFFFF)
    public static let clear = Color(red: 0, green: 0, blue: 0, alpha: 0)

    public var isClear: Bool { alpha == 0 }

    /// `#rrggbb`, or `#rrggbbaa` when not fully opaque.
    public var hexString: String {
        let c = [red, green, blue].map { String(format: "%02x", Int(($0 * 255).rounded())) }.joined()
        return alpha >= 1 ? "#\(c)" : "#\(c)" + String(format: "%02x", Int((alpha * 255).rounded()))
    }

    public var description: String { hexString }

    public func withAlpha(_ alpha: Double) -> Color {
        Color(red: red, green: green, blue: blue, alpha: alpha)
    }

    /// Relative luminance per WCAG 2.
    public var luminance: Double {
        func linear(_ c: Double) -> Double { c <= 0.03928 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    public var isDark: Bool { luminance < 0.5 }
}

// MARK: - HSL adjustments

extension Color {
    /// Hue in degrees, saturation and lightness in 0...1.
    public var hsl: (hue: Double, saturation: Double, lightness: Double) {
        let maxC = max(red, green, blue), minC = min(red, green, blue)
        let l = (maxC + minC) / 2
        guard maxC != minC else { return (0, 0, l) }
        let d = maxC - minC
        let s = l > 0.5 ? d / (2 - maxC - minC) : d / (maxC + minC)
        var h: Double
        switch maxC {
        case red: h = (green - blue) / d + (green < blue ? 6 : 0)
        case green: h = (blue - red) / d + 2
        default: h = (red - green) / d + 4
        }
        h *= 60
        return (h, s, l)
    }

    public init(hue: Double, saturation: Double, lightness: Double, alpha: Double = 1) {
        let h = (hue.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) / 360
        let s = saturation.clamped(to: 0...1), l = lightness.clamped(to: 0...1)
        guard s > 0 else { self.init(red: l, green: l, blue: l, alpha: alpha); return }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t: Double) -> Double {
            let t = t < 0 ? t + 1 : (t > 1 ? t - 1 : t)
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }
            if t < 0.5 { return q }
            if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }
            return p
        }
        self.init(red: channel(h + 1.0 / 3), green: channel(h), blue: channel(h - 1.0 / 3), alpha: alpha)
    }

    /// Adjusts HSL components by the given deltas (hue in degrees,
    /// saturation and lightness in percentage points), like khroma's
    /// `adjust`, which Mermaid themes use to derive their palettes.
    public func adjusted(hue: Double = 0, saturation: Double = 0, lightness: Double = 0) -> Color {
        let c = hsl
        return Color(hue: c.hue + hue, saturation: c.saturation + saturation / 100,
                     lightness: c.lightness + lightness / 100, alpha: alpha)
    }

    public func lightened(_ percent: Double) -> Color { adjusted(lightness: percent) }
    public func darkened(_ percent: Double) -> Color { adjusted(lightness: -percent) }

    public var inverted: Color { Color(red: 1 - red, green: 1 - green, blue: 1 - blue, alpha: alpha) }

    /// Linear interpolation toward `other`; `amount` 0 returns self.
    public func mixed(with other: Color, amount: Double) -> Color {
        let t = amount.clamped(to: 0...1)
        return Color(red: red + (other.red - red) * t, green: green + (other.green - green) * t,
                     blue: blue + (other.blue - blue) * t, alpha: alpha + (other.alpha - alpha) * t)
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self { min(max(self, range.lowerBound), range.upperBound) }
}
