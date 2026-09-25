extension SequenceDiagram: Diagram {
    public func scene(in context: RenderContext) throws -> Scene {
        let settings = SequenceSettings(context: context)
        let layout = SequenceLayoutBuilder.layout(self, settings: settings, measurer: context.measurer)
        let items = SequenceSceneBuilder(layout: layout, settings: settings, palette: SequencePalette(theme: context.theme)).items()
        // Content can reach left of the first lifeline (notes, frames), so
        // measure the drawn items and move them to the origin.
        let bounds = items.compactMap(\.drawnBounds).reduce(nil) { $0?.union($1) ?? $1 } ?? Rect(x: 0, y: 0, width: 0, height: 0)
        let inset = max(0, settings.diagramMarginX - settings.diagramMarginY)
        let content = items.map { $0.offsetBy(dx: inset - bounds.minX, dy: -bounds.minY) }
        let canvas = DiagramCanvas(context: context, margin: settings.diagramMarginY, title: title)
        return canvas.scene(content: content, size: Size(bounds.width + 2 * inset, bounds.height))
    }
}

fileprivate extension SceneItem {
    /// The extent of the item's paths and text frames.
    var drawnBounds: Rect? {
        switch self {
        case .shape(let shape):
            guard let rect = shape.path.bounds else { return nil }
            let half = (shape.stroke?.width ?? 0) / 2
            return rect.insetBy(dx: -half, dy: -half)
        case .text(let text): return text.frame
        case .group(let group): return group.items.compactMap(\.drawnBounds).reduce(nil) { $0?.union($1) ?? $1 }
        }
    }
}
