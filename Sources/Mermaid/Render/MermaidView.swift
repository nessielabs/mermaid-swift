#if canImport(SwiftUI) && canImport(CoreText)
import CoreGraphics
import SwiftUI

/// Displays a Mermaid diagram natively.
///
/// ```swift
/// MermaidView("""
/// flowchart LR
///   A --> B
/// """)
/// ```
///
/// Without an explicit theme the view follows the environment's color
/// scheme, drawing with Mermaid's `dark` theme in dark mode unless the
/// diagram's own configuration selects a theme. The diagram keeps its
/// natural size and scales down to fit narrower containers. Source that
/// fails to parse shows its located error.
public struct MermaidView: View {
    private let parsed: Result<ParsedDiagram, Error>
    private let options: RenderOptions
    private let followsColorScheme: Bool
    @Environment(\.colorScheme) private var colorScheme

    public init(_ source: String, options: RenderOptions = RenderOptions(background: .transparent)) {
        parsed = Result { try Mermaid.parse(source) }
        self.options = options
        followsColorScheme = options.theme == nil
    }

    public var body: some View {
        switch parsed.flatMap({ diagram in Result { try diagram.scene(options: resolvedOptions(for: diagram)) } }) {
        case .success(let scene):
            SceneView(scene: scene)
                .accessibilityElement()
                .accessibilityLabel(scene.accessibilityTitle ?? "Diagram")
                .accessibilityHint(scene.accessibilityDescription ?? "")
        case .failure(let error):
            Text(String(describing: error))
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.red)
                .textSelection(.enabled)
        }
    }

    private func resolvedOptions(for diagram: ParsedDiagram) -> RenderOptions {
        var options = options
        if followsColorScheme, colorScheme == .dark, diagram.config["theme"] == nil {
            options.theme = Theme(config: diagram.config, fallback: .dark)
        }
        return options
    }
}

/// Draws a prepared scene, scaled down proportionally when space is tight.
public struct SceneView: View {
    public let scene: Scene

    public init(scene: Scene) {
        self.scene = scene
    }

    public var body: some View {
        let size = CGSize(width: scene.size.width, height: scene.size.height)
        ViewThatFits(in: .horizontal) {
            canvas.frame(width: size.width, height: size.height)
            canvas.aspectRatio(size, contentMode: .fit).frame(maxWidth: size.width)
        }
    }

    private var canvas: some View {
        Canvas { context, canvasSize in
            let scale = min(canvasSize.width / scene.size.width, canvasSize.height / scene.size.height)
            context.withCGContext { cg in
                cg.scaleBy(x: scale, y: scale)
                CoreGraphicsRenderer.draw(scene, in: cg)
            }
        }
    }
}
#endif
