#if canImport(CoreGraphics) && canImport(CoreText)
import CoreGraphics
import CoreText
import Foundation

/// Draws scenes with CoreGraphics and CoreText.
public enum CoreGraphicsRenderer {
    /// Draws `scene` into a context whose user space has its origin at the
    /// top left and y increasing downward (UIKit, SwiftUI `Canvas`, and
    /// flipped AppKit views). Use `makeImage` for bitmap output, which sets
    /// that orientation up itself.
    public static func draw(_ scene: Scene, in context: CGContext, fonts: FontResolver = .shared) {
        context.saveGState()
        defer { context.restoreGState() }
        if let background = scene.background, !background.isClear {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: scene.size.width, height: scene.size.height))
        }
        for item in scene.items { draw(item, in: context, fonts: fonts) }
    }

    /// Renders `scene` into a new sRGB bitmap at `scale` pixels per point.
    public static func makeImage(_ scene: Scene, scale: Double = 2, fonts: FontResolver = .shared) -> CGImage? {
        let width = Int((scene.size.width * scale).rounded(.up))
        let height = Int((scene.size.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Bitmap contexts are y-up; flip to the scene's y-down space.
        context.translateBy(x: 0, y: CGFloat(height))
        context.scaleBy(x: CGFloat(scale), y: -CGFloat(scale))
        draw(scene, in: context, fonts: fonts)
        return context.makeImage()
    }

    private static func draw(_ item: SceneItem, in context: CGContext, fonts: FontResolver) {
        switch item {
        case .shape(let shape): draw(shape, in: context)
        case .text(let text): draw(text, in: context, fonts: fonts)
        case .group(let group): for child in group.items { draw(child, in: context, fonts: fonts) }
        }
    }

    private static func draw(_ shape: ShapeItem, in context: CGContext) {
        let path = shape.path.cgPath
        context.saveGState()
        defer { context.restoreGState() }
        context.setAlpha(CGFloat(shape.opacity))
        if let gradient = shape.gradient, let cgGradient = gradient.cgGradient {
            context.saveGState()
            context.addPath(path)
            context.clip()
            context.drawLinearGradient(cgGradient, start: CGPoint(x: gradient.start.x, y: gradient.start.y),
                                       end: CGPoint(x: gradient.end.x, y: gradient.end.y),
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            context.restoreGState()
        } else if let fill = shape.fill, !fill.isClear {
            context.addPath(path)
            context.setFillColor(fill.cgColor)
            context.fillPath()
        }
        if let stroke = shape.stroke, !stroke.color.isClear, stroke.width > 0 {
            context.addPath(path)
            context.setStrokeColor(stroke.color.cgColor)
            context.setLineWidth(CGFloat(stroke.width))
            context.setLineDash(phase: 0, lengths: stroke.dash.map { CGFloat($0) })
            context.setLineCap(stroke.cap == .round ? .round : stroke.cap == .square ? .square : .butt)
            context.setLineJoin(stroke.join == .round ? .round : stroke.join == .bevel ? .bevel : .miter)
            context.strokePath()
        }
    }

    private static func draw(_ text: TextItem, in context: CGContext, fonts: FontResolver) {
        context.saveGState()
        defer { context.restoreGState() }
        if text.rotation != 0 {
            context.translateBy(x: text.frame.midX, y: text.frame.midY)
            context.rotate(by: CGFloat(text.rotation * .pi / 180))
            context.translateBy(x: -text.frame.midX, y: -text.frame.midY)
        }
        let color = text.color.cgColor
        for line in text.block.lines {
            let origin = text.lineOrigin(line)
            for run in line.runs where !run.text.isEmpty {
                let attributes: [NSAttributedString.Key: Any] = [
                    kCTFontAttributeName as NSAttributedString.Key: fonts.ctFont(for: run.font),
                    kCTForegroundColorAttributeName as NSAttributedString.Key: color,
                ]
                let ctLine = CTLineCreateWithAttributedString(NSAttributedString(string: run.text, attributes: attributes))
                context.saveGState()
                // CoreText lays glyphs out y-up; flip locally at the baseline.
                context.translateBy(x: origin.x + run.x, y: origin.y)
                context.scaleBy(x: 1, y: -1)
                context.textPosition = .zero
                CTLineDraw(ctLine, context)
                context.restoreGState()
                if run.strikethrough {
                    let y = origin.y - run.font.size * 0.3
                    context.setStrokeColor(color)
                    context.setLineWidth(max(1, run.font.size / 14))
                    context.strokeLineSegments(between: [CGPoint(x: origin.x + run.x, y: y),
                                                         CGPoint(x: origin.x + run.x + run.width, y: y)])
                }
            }
        }
    }
}

extension Color {
    var cgColor: CGColor { CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha) }
}

extension LinearGradient {
    var cgGradient: CGGradient? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        return CGGradient(colorsSpace: space, colors: stops.map(\.color.cgColor) as CFArray,
                          locations: stops.map { CGFloat($0.offset) })
    }
}

extension Path {
    var cgPath: CGPath {
        let path = CGMutablePath()
        for element in elements {
            switch element {
            case .move(let p): path.move(to: CGPoint(x: p.x, y: p.y))
            case .line(let p): path.addLine(to: CGPoint(x: p.x, y: p.y))
            case .curve(let a, let b, let p):
                path.addCurve(to: CGPoint(x: p.x, y: p.y), control1: CGPoint(x: a.x, y: a.y),
                              control2: CGPoint(x: b.x, y: b.y))
            case .close: path.closeSubpath()
            }
        }
        return path
    }
}
#endif
