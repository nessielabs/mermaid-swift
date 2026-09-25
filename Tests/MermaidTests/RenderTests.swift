import Testing
@testable import Mermaid
#if canImport(CoreGraphics)
import CoreGraphics
#endif

@Suite("Renderers")
struct RenderTests {
    /// A 100×100 scene with a black bar across the top quarter and a label
    /// in the top half.
    var scene: Scene {
        let block = TextBlock(RichText(plain: "Top"), font: Font(size: 14), measurer: ApproximateTextMeasurer())
        return Scene(size: Size(100, 100), background: .white, items: [
            .shape(ShapeItem(.rect(Rect(x: 0, y: 0, width: 100, height: 25)), fill: .black)),
            .text(TextItem(block, centeredAt: Point(50, 40), color: Color(hex: 0xFF0000))),
        ], accessibilityTitle: "A <test>")
    }

    @Test func svgContainsAccessibleStructure() {
        let svg = scene.svg
        #expect(svg.hasPrefix("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\""))
        #expect(svg.contains("<title id=\"title\">A &lt;test&gt;</title>"))
        #expect(svg.contains("<path d=\"M0 0L100 0L100 25L0 25Z\" fill=\"#000000\"/>"))
        #expect(svg.contains(">Top</text>"))
    }

    @Test func svgNumbersAreCompact() {
        #expect(SVGRenderer.n(1.006) == "1.01")
        #expect(SVGRenderer.n(2.50) == "2.5")
        #expect(SVGRenderer.n(-0.0001) == "0")
    }

    #if canImport(CoreGraphics) && canImport(CoreText)
    @Test func bitmapsAreUpright() throws {
        let image = try #require(scene.cgImage(scale: 1))
        #expect(image.width == 100 && image.height == 100)
        let pixels = try #require(Self.rgba(image))
        func pixel(_ x: Int, _ y: Int) -> (Int, Int, Int) {
            let i = (y * 100 + x) * 4
            return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
        }
        // Row 0 is the top of the image: the bar must be there, not at the bottom.
        #expect(pixel(50, 5) == (0, 0, 0))
        #expect(pixel(50, 95) == (255, 255, 255))
        // The red label sits in rows 25..<60, never mirrored into the bottom half.
        let redRows = (0..<100).filter { y in (0..<100).contains { x in
            let p = pixel(x, y); return p.0 > 150 && p.1 < 100 && p.2 < 100 } }
        #expect(!redRows.isEmpty)
        #expect(redRows.allSatisfy { $0 >= 25 && $0 < 60 })
    }

    @Test func pngEncodes() throws {
        let data = try #require(scene.pngData(scale: 2))
        #expect(data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
    }

    static func rgba(_ image: CGImage) -> [UInt8]? {
        var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
        guard let context = CGContext(data: &pixels, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return pixels
    }
    #endif
}
