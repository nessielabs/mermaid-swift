#if canImport(ImageIO) && canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

extension Scene {
    /// Renders the scene to a bitmap at `scale` pixels per point.
    public func cgImage(scale: Double = 2) -> CGImage? {
        CoreGraphicsRenderer.makeImage(self, scale: scale)
    }

    /// Encodes the rendered scene as PNG.
    public func pngData(scale: Double = 2) -> Data? {
        guard let image = cgImage(scale: scale) else { return nil }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            return nil
        }
        let dpi = 72 * scale
        let properties = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi] as CFDictionary
        CGImageDestinationAddImage(destination, image, properties)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
}
#endif

extension Scene {
    /// The scene as a standalone SVG document.
    public var svg: String { SVGRenderer.render(self) }
}
