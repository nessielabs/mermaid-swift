import Foundation

/// Serializes a scene as a standalone SVG document.
public enum SVGRenderer {
    public static func render(_ scene: Scene) -> String {
        var out = """
        <svg xmlns="http://www.w3.org/2000/svg" width="\(n(scene.size.width))" height="\(n(scene.size.height))" \
        viewBox="0 0 \(n(scene.size.width)) \(n(scene.size.height))" role="img"
        """
        if scene.accessibilityTitle != nil { out += " aria-labelledby=\"title\"" }
        out += ">"
        if let title = scene.accessibilityTitle { out += "<title id=\"title\">\(escape(title))</title>" }
        if let desc = scene.accessibilityDescription { out += "<desc>\(escape(desc))</desc>" }
        if let background = scene.background, !background.isClear {
            out += "<rect width=\"100%\" height=\"100%\"\(paint("fill", background))/>"
        }
        for item in scene.items { write(item, into: &out) }
        out += "</svg>"
        return out
    }

    private static func write(_ item: SceneItem, into out: inout String) {
        switch item {
        case .shape(let shape): write(shape, into: &out)
        case .text(let text): write(text, into: &out)
        case .group(let group):
            out += "<g"
            if let id = group.id { out += " id=\"\(escape(id))\"" }
            if let role = group.role { out += " class=\"\(escape(role))\"" }
            out += ">"
            for child in group.items { write(child, into: &out) }
            out += "</g>"
        }
    }

    private static func write(_ shape: ShapeItem, into out: inout String) {
        var gradientID: String?
        if let gradient = shape.gradient {
            let id = gradientIdentifier(gradient)
            gradientID = id
            out += "<defs><linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\""
            out += " x1=\"\(n(gradient.start.x))\" y1=\"\(n(gradient.start.y))\""
            out += " x2=\"\(n(gradient.end.x))\" y2=\"\(n(gradient.end.y))\">"
            for stop in gradient.stops {
                out += "<stop offset=\"\(n(stop.offset))\" stop-color=\"\(stop.color.withAlpha(1).hexString)\""
                if stop.color.alpha < 1 { out += " stop-opacity=\"\(n(stop.color.alpha))\"" }
                out += "/>"
            }
            out += "</linearGradient></defs>"
        }
        out += "<path d=\"\(pathData(shape.path))\""
        if let gradientID {
            out += " fill=\"url(#\(gradientID))\""
        } else {
            out += shape.fill.map { paint("fill", $0) } ?? " fill=\"none\""
        }
        if let stroke = shape.stroke {
            out += paint("stroke", stroke.color) + " stroke-width=\"\(n(stroke.width))\""
            if !stroke.dash.isEmpty { out += " stroke-dasharray=\"\(stroke.dash.map(n).joined(separator: " "))\"" }
            if stroke.cap != .butt { out += " stroke-linecap=\"\(stroke.cap.rawValue)\"" }
            if stroke.join != .miter { out += " stroke-linejoin=\"\(stroke.join.rawValue)\"" }
        }
        if shape.opacity < 1 { out += " opacity=\"\(n(shape.opacity))\"" }
        out += "/>"
    }

    private static func write(_ text: TextItem, into out: inout String) {
        guard !text.block.isEmpty else { return }
        let rotate = text.rotation == 0 ? "" :
            " transform=\"rotate(\(n(text.rotation)) \(n(text.frame.midX)) \(n(text.frame.midY)))\""
        out += "<g\(rotate)\(paint("fill", text.color))>"
        for line in text.block.lines {
            let origin = text.lineOrigin(line)
            for run in line.runs {
                out += "<text x=\"\(n(origin.x + run.x))\" y=\"\(n(origin.y))\""
                out += " font-family=\"\(escape(run.font.monospaced ? "monospace" : run.font.family))\""
                out += " font-size=\"\(n(run.font.size))\""
                if run.font.bold { out += " font-weight=\"bold\"" }
                if run.font.italic { out += " font-style=\"italic\"" }
                if run.strikethrough { out += " text-decoration=\"line-through\"" }
                out += " xml:space=\"preserve\">\(escape(run.text))</text>"
            }
        }
        out += "</g>"
    }

    /// A deterministic id derived from the gradient's content (FNV-1a), so
    /// identical documents serialize identically and identical gradients
    /// may share a definition.
    static func gradientIdentifier(_ gradient: LinearGradient) -> String {
        var text = "\(n(gradient.start.x)),\(n(gradient.start.y)),\(n(gradient.end.x)),\(n(gradient.end.y))"
        for stop in gradient.stops { text += ";\(n(stop.offset))\(stop.color.hexString)" }
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return "gradient-" + String(hash, radix: 36)
    }

    static func pathData(_ path: Path) -> String {
        path.elements.map { element in
            switch element {
            case .move(let p): return "M\(n(p.x)) \(n(p.y))"
            case .line(let p): return "L\(n(p.x)) \(n(p.y))"
            case .curve(let a, let b, let p):
                return "C\(n(a.x)) \(n(a.y)) \(n(b.x)) \(n(b.y)) \(n(p.x)) \(n(p.y))"
            case .close: return "Z"
            }
        }.joined()
    }

    private static func paint(_ attribute: String, _ color: Color) -> String {
        let opaque = color.withAlpha(1).hexString
        return color.alpha < 1
            ? " \(attribute)=\"\(opaque)\" \(attribute)-opacity=\"\(n(color.alpha))\""
            : " \(attribute)=\"\(opaque)\""
    }

    /// Formats numbers with at most two decimals and no trailing zeros.
    static func n(_ value: Double) -> String {
        let rounded = (value * 100).rounded() / 100
        if rounded == rounded.rounded() { return String(Int(rounded)) }
        var text = String(format: "%.2f", rounded)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }

    static func escape(_ text: String) -> String {
        var out = ""
        for c in text {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(c)
            }
        }
        return out
    }
}
