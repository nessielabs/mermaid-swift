import Foundation

/// Helpers shared by the chart diagrams (pie, quadrant, XY, radar,
/// sankey): theme variables that are not colors or live in nested
/// objects, and text placed by an anchor point the way SVG's
/// `text-anchor` and `dominant-baseline` place it.
extension RenderContext {
    /// A raw theme variable, following nested keys such as
    /// `themeVariable("xyChart", "titleColor")`.
    func themeVariable(_ path: String...) -> ConfigValue? {
        var value = config["themeVariables"]
        for key in path { value = value?[key] }
        return value
    }

    /// A color theme variable. Top-level variables resolve through the
    /// theme (so `RenderOptions.theme` overrides apply); nested ones come
    /// from configuration. Bare hex digits (`ff0000`) are accepted, as
    /// browsers accept them in mermaid's generated CSS.
    func themeColor(_ path: String..., default fallback: Color) -> Color {
        if path.count == 1, let color = theme.color(path[0]) { return color }
        var value = config["themeVariables"]
        for key in path { value = value?[key] }
        guard let text = value?.stringValue?.trimmingWhitespace() else { return fallback }
        return Color(css: text) ?? Color(css: "#" + text) ?? fallback
    }

    /// A numeric theme variable such as `pieOuterStrokeWidth: "2px"`.
    func themeNumber(_ path: String..., default fallback: Double) -> Double {
        var value = config["themeVariables"]
        for key in path { value = value?[key] }
        return value?.numberValue ?? fallback
    }
}

/// How text sits relative to its anchor point.
struct TextAnchor: Hashable, Sendable {
    enum Horizontal: Hashable, Sendable { case start, middle, end }
    enum Vertical: Hashable, Sendable { case top, middle, bottom }

    var horizontal: Horizontal
    var vertical: Vertical

    static let center = TextAnchor(horizontal: .middle, vertical: .middle)
    static let topCenter = TextAnchor(horizontal: .middle, vertical: .top)
    static let bottomCenter = TextAnchor(horizontal: .middle, vertical: .bottom)
    static let leading = TextAnchor(horizontal: .start, vertical: .middle)
    static let trailing = TextAnchor(horizontal: .end, vertical: .middle)
}

extension TextItem {
    /// Places `block` so that its anchor lands on `point`. With a rotation,
    /// the anchor is taken in the text's own (rotated) frame, as SVG's
    /// `translate(x, y) rotate(r)` does; rotations are about the anchor.
    init(_ block: TextBlock, at point: Point, anchor: TextAnchor, color: Color, rotation: Double = 0) {
        let alongX: Double
        switch anchor.horizontal {
        case .start: alongX = block.width / 2
        case .middle: alongX = 0
        case .end: alongX = -block.width / 2
        }
        let alongY: Double
        switch anchor.vertical {
        case .top: alongY = block.height / 2
        case .middle: alongY = 0
        case .bottom: alongY = -block.height / 2
        }
        let radians = rotation * .pi / 180
        let center = Point(point.x + alongX * cos(radians) - alongY * sin(radians),
                           point.y + alongX * sin(radians) + alongY * cos(radians))
        let alignment: Alignment = anchor.horizontal == .start ? .leading : anchor.horizontal == .end ? .trailing : .center
        self.init(block, frame: Rect(center: center, size: Size(block.width, block.height)),
                  alignment: alignment, color: color, rotation: rotation)
    }

    /// The axis-aligned box the (possibly rotated) text occupies.
    var bounds: Rect {
        let radians = rotation * .pi / 180
        let w = abs(frame.width * cos(radians)) + abs(frame.height * sin(radians))
        let h = abs(frame.width * sin(radians)) + abs(frame.height * cos(radians))
        return Rect(center: frame.center, size: Size(w, h))
    }
}
