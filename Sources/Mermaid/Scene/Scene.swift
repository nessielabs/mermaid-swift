/// A fully laid-out diagram: everything needed to draw it, in diagram
/// space, independent of any rendering technology.
///
/// Every diagram type produces a scene; the SVG, CoreGraphics, and SwiftUI
/// renderers only ever consume scenes.
public struct Scene: Hashable, Sendable {
    public var size: Size
    public var background: Color?
    public var items: [SceneItem]
    /// Accessible title (`accTitle` or the front matter title).
    public var accessibilityTitle: String?
    /// Accessible description (`accDescr`).
    public var accessibilityDescription: String?

    public init(size: Size, background: Color? = nil, items: [SceneItem],
                accessibilityTitle: String? = nil, accessibilityDescription: String? = nil) {
        self.size = size
        self.background = background
        self.items = items
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityDescription = accessibilityDescription
    }
}

public enum SceneItem: Hashable, Sendable {
    case shape(ShapeItem)
    case text(TextItem)
    case group(GroupItem)
}

public struct Stroke: Hashable, Sendable {
    public enum Cap: String, Hashable, Sendable { case butt, round, square }
    public enum Join: String, Hashable, Sendable { case miter, round, bevel }

    public var color: Color
    public var width: Double
    public var dash: [Double]
    public var cap: Cap
    public var join: Join

    public init(_ color: Color, width: Double = 1, dash: [Double] = [], cap: Cap = .butt, join: Join = .miter) {
        self.color = color
        self.width = width
        self.dash = dash
        self.cap = cap
        self.join = join
    }
}

public struct ShapeItem: Hashable, Sendable {
    public var path: Path
    public var fill: Color?
    public var stroke: Stroke?
    public var opacity: Double
    /// A gradient that fills the path instead of `fill` when set.
    public var gradient: LinearGradient?

    public init(_ path: Path, fill: Color? = nil, stroke: Stroke? = nil, opacity: Double = 1,
                gradient: LinearGradient? = nil) {
        self.path = path
        self.fill = fill
        self.stroke = stroke
        self.opacity = opacity
        self.gradient = gradient
    }
}

/// A linear color ramp between two points in diagram space, such as the
/// source-to-target blend of a sankey link.
public struct LinearGradient: Hashable, Sendable {
    public struct Stop: Hashable, Sendable {
        /// Position along the gradient axis, 0...1.
        public var offset: Double
        public var color: Color

        public init(offset: Double, color: Color) {
            self.offset = offset
            self.color = color
        }
    }

    public var start: Point
    public var end: Point
    public var stops: [Stop]

    public init(start: Point, end: Point, stops: [Stop]) {
        self.start = start
        self.end = end
        self.stops = stops
    }

    /// A two-color gradient from `start` to `end`.
    public init(from startColor: Color, at start: Point, to endColor: Color, at end: Point) {
        self.init(start: start, end: end, stops: [Stop(offset: 0, color: startColor), Stop(offset: 1, color: endColor)])
    }
}

public struct TextItem: Hashable, Sendable {
    public enum Alignment: String, Hashable, Sendable { case leading, center, trailing }

    public var block: TextBlock
    /// The box the text is placed in. The block is centered vertically and
    /// aligned horizontally within it.
    public var frame: Rect
    public var alignment: Alignment
    public var color: Color
    /// Clockwise rotation in degrees about the frame's center.
    public var rotation: Double

    public init(_ block: TextBlock, frame: Rect, alignment: Alignment = .center, color: Color, rotation: Double = 0) {
        self.block = block
        self.frame = frame
        self.alignment = alignment
        self.color = color
        self.rotation = rotation
    }

    /// Centers `block` at `center`.
    public init(_ block: TextBlock, centeredAt center: Point, color: Color, rotation: Double = 0) {
        self.init(block, frame: Rect(center: center, size: Size(block.width, block.height)),
                  alignment: .center, color: color, rotation: rotation)
    }

    /// The x offset of a line's start within the frame.
    public func lineOrigin(_ line: TextBlock.Line) -> Point {
        let top = frame.minY + (frame.height - block.height) / 2
        let x: Double
        switch alignment {
        case .leading: x = frame.minX
        case .center: x = frame.midX - line.width / 2
        case .trailing: x = frame.maxX - line.width
        }
        return Point(x, top + line.baseline)
    }
}

public struct GroupItem: Hashable, Sendable {
    /// A semantic name for the group (a node or edge id), emitted as an SVG
    /// id so exported diagrams stay inspectable and styleable.
    public var id: String?
    public var role: String?
    public var items: [SceneItem]

    public init(id: String? = nil, role: String? = nil, items: [SceneItem]) {
        self.id = id
        self.role = role
        self.items = items
    }
}
