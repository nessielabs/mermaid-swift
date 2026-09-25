#if canImport(SwiftUI) && canImport(CoreText)
import CoreGraphics
import SwiftUI
import Testing
@testable import Mermaid

@Suite("SwiftUI view")
@MainActor
struct MermaidViewTests {
    @Test func sceneViewDrawsUprightThroughSwiftUI() throws {
        let scene = Scene(size: Size(100, 100), background: .white, items: [
            .shape(ShapeItem(.rect(Rect(x: 0, y: 0, width: 100, height: 25)), fill: .black)),
        ])
        let renderer = ImageRenderer(content: SceneView(scene: scene))
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        let pixels = try #require(RenderTests.rgba(image))
        let row = { (y: Int) -> Int in (y * image.width + image.width / 2) * 4 }
        #expect(pixels[row(5)] < 20)
        #expect(pixels[row(image.height - 5)] > 235)
    }

    @Test func viewRendersDiagramsAndErrors() throws {
        let diagram = ImageRenderer(content: MermaidView("flowchart LR\n  A --> B"))
        #expect(diagram.cgImage != nil)
        let broken = ImageRenderer(content: MermaidView("flowchart LR\n  A --> "))
        #expect(broken.cgImage != nil)
    }
}
#endif
