/// Wraps laid-out diagram content with a margin and an optional title,
/// producing the final scene. Every diagram type finishes through here so
/// margins and titles look the same everywhere.
struct DiagramCanvas {
    var context: RenderContext
    /// Space around the content.
    var margin: Double = 8
    /// Title text; defaults to the front matter title.
    var title: String?
    var titleSize: Double = 18

    init(context: RenderContext, margin: Double = 8, title: String? = nil) {
        self.context = context
        self.margin = margin
        self.title = title ?? context.title
    }

    /// Positions `content` (drawn with its origin at 0,0 and extent `size`)
    /// below the title, centered horizontally when the title is wider.
    func scene(content: [SceneItem], size: Size) -> Scene {
        var items: [SceneItem] = []
        var titleHeight = 0.0
        var titleBlock: TextBlock?
        if let title, !title.isEmpty {
            let block = context.label(title, size: titleSize, bold: false)
            titleBlock = block
            titleHeight = block.height + 12
        }
        let width = max(size.width, titleBlock?.width ?? 0) + 2 * margin
        let dx = margin + (width - 2 * margin - size.width) / 2
        let dy = margin + titleHeight
        if let titleBlock {
            items.append(.text(TextItem(titleBlock, centeredAt: Point(width / 2, margin + titleBlock.height / 2),
                                        color: context.theme.titleColor)))
        }
        items += content.map { $0.offsetBy(dx: dx, dy: dy) }
        return Scene(size: Size(width, size.height + 2 * margin + titleHeight), items: items)
    }
}

extension SceneItem {
    /// The item translated by (dx, dy).
    public func offsetBy(dx: Double, dy: Double) -> SceneItem {
        guard dx != 0 || dy != 0 else { return self }
        switch self {
        case .shape(var shape):
            shape.path = shape.path.offsetBy(dx: dx, dy: dy)
            return .shape(shape)
        case .text(var text):
            text.frame = text.frame.offsetBy(dx: dx, dy: dy)
            return .text(text)
        case .group(var group):
            group.items = group.items.map { $0.offsetBy(dx: dx, dy: dy) }
            return .group(group)
        }
    }
}
