/// Vector versions of mermaid's built-in architecture icons: white line
/// art on a blue square, drawn in an 80×80 design space and scaled to
/// the requested frame.
///
/// Names outside the built-in set (such as iconify names like
/// `logos:aws-s3`, which mermaid.js resolves from registered icon packs)
/// draw a question mark, as mermaid.js does for unknown icons.
enum ArchitectureIcons {
    static let builtIn: Set<String> = ["cloud", "database", "disk", "internet", "server", "blank"]
    static let background = Color(hex: 0x087EBF)

    static func items(_ name: String, in frame: Rect, glyph: Color = .white) -> [SceneItem] {
        let s = frame.width / 80
        func p(_ x: Double, _ y: Double) -> Point { Point(frame.minX + x * s, frame.minY + y * s) }
        let stroke = Stroke(glyph, width: max(1, 2 * s), cap: .round, join: .round)
        var items: [SceneItem] = [.shape(ShapeItem(.rect(frame), fill: background))]
        func line(_ path: Path) { items.append(.shape(ShapeItem(path, stroke: stroke))) }
        func fill(_ path: Path) { items.append(.shape(ShapeItem(path, fill: glyph))) }
        func ellipse(_ cx: Double, _ cy: Double, _ rx: Double, _ ry: Double) -> Path {
            .ellipse(in: Rect(center: p(cx, cy), size: Size(2 * rx * s, 2 * ry * s)))
        }

        switch name {
        case "blank":
            break
        case "database":
            line(ellipse(40, 22.14, 20, 7.14))
            line(.polyline([p(20, 22.14), p(20, 57.86)]))
            line(.polyline([p(60, 22.14), p(60, 57.86)]))
            for y in [34.05, 45.95, 57.86] {
                var arc = Path()
                arc.appendArc(center: p(40, y), radiusX: 20 * s, radiusY: 7.14 * s, from: 180, to: 0, connect: false)
                line(arc)
            }
        case "server":
            line(.rect(Rect(x: frame.minX + 17.5 * s, y: frame.minY + 17.5 * s, width: 45 * s, height: 45 * s), cornerRadius: 2 * s))
            line(.polyline([p(17.5, 32.5), p(62.5, 32.5)]))
            line(.polyline([p(17.5, 47.5), p(62.5, 47.5)]))
            for y in [25.0, 40, 55] {
                fill(.rect(Rect(x: frame.minX + 43.75 * s, y: frame.minY + (y - 0.75) * s, width: 12.5 * s, height: 1.5 * s), cornerRadius: 0.75 * s))
                for x in [22.5, 27.5, 32.5] { fill(.circle(center: p(x, y), radius: 1.2 * s)) }
            }
        case "disk":
            line(.rect(Rect(x: frame.minX + 20 * s, y: frame.minY + 15 * s, width: 40 * s, height: 50 * s), cornerRadius: s))
            for (x, y) in [(24.0, 19.17), (56, 19.17), (24, 60.83), (56, 60.83)] { fill(.circle(center: p(x, y), radius: 1.2 * s)) }
            line(ellipse(40, 33.75, 14, 14.58))
            line(ellipse(40, 33.75, 4, 4.17))
            fill(.polygon([p(37.5, 42.5), p(32.7, 55.7), p(26.4, 52.1), p(35.4, 41.3)]))
        case "internet":
            line(.circle(center: p(40, 40), radius: 22.5 * s))
            line(.polyline([p(40, 17.5), p(40, 62.5)]))
            line(.polyline([p(17.5, 40), p(62.5, 40)]))
            line(.polyline([p(19.75, 30.1), p(60.25, 30.1)]))
            line(.polyline([p(19.75, 49.9), p(60.25, 49.9)]))
            for k in [-1.0, 1] {
                var meridian = Path()
                meridian.move(to: p(40, 17.5))
                meridian.curve(to: p(40, 62.5), control1: p(40 + 15.28 * k, 28.6), control2: p(40 + 15.28 * k, 51.4))
                line(meridian)
            }
        case "cloud":
            var cloud = Path()
            cloud.move(to: p(65, 47.5))
            let segments: [(Double, Double, Double, Double, Double, Double)] = [
                (65, 50.26, 62.76, 52.5, 60, 52.5), (20, 52.5, 20, 52.5, 20, 52.5),
                (17.24, 52.5, 15, 50.26, 15, 47.5), (15, 45.63, 16.03, 43.99, 17.56, 43.14),
                (17.52, 42.93, 17.5, 42.72, 17.5, 42.5), (17.5, 39.9, 19.98, 37.76, 23.15, 37.53),
                (24.8, 33.02, 29.49, 29.77, 35, 29.77), (35.86, 29.77, 36.69, 29.85, 37.5, 30),
                (39.59, 28.43, 42.19, 27.5, 45, 27.5), (51.1, 27.5, 56.19, 31.88, 57.28, 37.67),
                (59.42, 38.23, 61, 40.18, 61, 42.5), (61, 42.53, 61, 42.57, 60.99, 42.6),
                (63.28, 43.06, 65, 45.08, 65, 47.5),
            ]
            for (x1, y1, x2, y2, x, y) in segments { cloud.curve(to: p(x, y), control1: p(x1, y1), control2: p(x2, y2)) }
            cloud.close()
            line(cloud)
        default:
            let block = TextBlock(RichText(plain: "?"), font: Font(size: 44 * s, bold: true), measurer: ApproximateTextMeasurer())
            items.append(.text(TextItem(block, centeredAt: frame.center, color: glyph)))
        }
        return items
    }
}
