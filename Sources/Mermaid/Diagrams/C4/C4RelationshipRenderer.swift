/// Draws C4 relationships: straight connectors between element outlines
/// (bowed apart when several connect the same pair), arrowheads per
/// relationship kind, and labels with the technology in brackets.
///
/// Labels sit at the middle of their line, displaced by any
/// `UpdateRelStyle` offsets. Unlike mermaid.js, a label that would cover an
/// element, a boundary title, or another label slides along its line to
/// the first free spot instead.
struct C4RelationshipRenderer {
    let diagram: C4Diagram
    let palette: C4Palette
    let measurer: any TextMeasurer
    /// Attachment outlines of elements and boundaries by alias.
    let outlines: [String: [Point]]
    /// Element frames that lines bow around.
    let elementFrames: [Rect]
    /// Areas labels should stay clear of (elements and boundary titles).
    let obstacles: [Rect]
    let background: Color

    /// Distance between parallel relationships connecting the same pair.
    static let parallelSpacing = 36.0

    func items() -> (lines: [SceneItem], labels: [SceneItem]) {
        let geometries = routes()
        var lines: [SceneItem] = [], labels: [SceneItem] = []
        // Labels avoid elements, titles, other labels, and arrow tips.
        var occupied = obstacles
        for geometry in geometries.compactMap({ $0 }) where geometry.route.count >= 2 {
            occupied += [geometry.start, geometry.end].map { Rect(center: $0, size: Size(18, 18)) }
        }
        for (i, rel) in diagram.relationships.enumerated() {
            guard let geometry = geometries[i], let source = outlines[rel.from], let target = outlines[rel.to] else { continue }
            let tag = rel.tags.compactMap { diagram.relationshipTags[$0] }.last
            let lineColor = rel.lineColor ?? tag?.lineColor ?? palette.neutralLine
            let textColor = rel.textColor ?? tag?.textColor ?? palette.neutralText
            let (width, dash) = Self.stroke(for: tag?.lineStyle)
            let connector = Connector(
                route: geometry.route, sourceOutline: source, targetOutline: target,
                curve: geometry.route.count > 2 ? .basis : .linear, color: lineColor, width: width, dash: dash,
                startMarker: rel.arrowAtSource ? .arrow : .none, endMarker: rel.arrowAtTarget ? .arrow : .none,
                label: nil, labelCenter: nil, labelColor: textColor, labelBackground: nil,
                background: background, id: "rel_\(rel.from)_\(rel.to)_\(i)")
            lines += connector.items()

            let label = RelationshipLabel(rel, number: diagram.kind == .dynamic ? i + 1 : nil,
                                          palette: palette, measurer: measurer)
            guard label.size.width > 0 else { continue }
            func isFree(_ point: Point) -> Bool {
                let box = Rect(center: point, size: label.size).insetBy(dx: -3, dy: -3)
                return !occupied.contains { $0.intersects(box) }
            }
            // Explicit offsets were tuned for mermaid.js's layout; they are
            // honored unless they would bury the label in an element.
            var candidates = geometry.labelCandidates()
            if rel.offsetX != nil || rel.offsetY != nil {
                candidates.insert(geometry.point(at: 0.5) + Point(rel.offsetX ?? 0, rel.offsetY ?? 0), at: 0)
            }
            let center = candidates.first(where: isFree) ?? candidates[0]
            occupied.append(Rect(center: center, size: label.size))
            labels.append(label.items(centeredAt: center, color: textColor, background: background, id: "rel_label_\(i)"))
        }
        return (lines, labels)
    }

    /// The path of every relationship (nil when an endpoint is missing).
    /// Relationships between the same pair fan apart; a straight line that
    /// would cross another element bows around it instead.
    private func routes() -> [RelationshipGeometry?] {
        var pairCounts: [Set<String>: Int] = [:]
        for rel in diagram.relationships { pairCounts[[rel.from, rel.to], default: 0] += 1 }
        var pairSeen: [Set<String>: Int] = [:]
        return diagram.relationships.map { rel in
            guard let source = outlines[rel.from], let target = outlines[rel.to],
                  let sourceBox = Rect.bounding(source), let targetBox = Rect.bounding(target) else { return nil }
            let pair: Set<String> = [rel.from, rel.to]
            let k = pairSeen[pair, default: 0]
            pairSeen[pair] = k + 1
            // Offsets are measured against a canonical direction so that
            // relationships in opposite directions still fan apart.
            let flip = rel.from > rel.to ? -1.0 : 1.0
            let offset = (Double(k) - Double(pairCounts[pair, default: 1] - 1) / 2) * Self.parallelSpacing * flip
            func geometry(_ bow: Double) -> RelationshipGeometry {
                RelationshipGeometry(from: sourceBox.center, to: targetBox.center, offset: offset + bow,
                                     isLoop: rel.from == rel.to, loopBox: sourceBox, source: source, target: target)
            }
            let others = elementFrames.filter { !$0.contains(sourceBox.center) && !$0.contains(targetBox.center) }
            for bow in [0.0, 70, -70, 140, -140, 210, -210] {
                let candidate = geometry(bow)
                if !candidate.crosses(others) { return candidate }
            }
            return geometry(0)
        }
    }

    /// C4-PlantUML's line styles from `AddRelTag($lineStyle=...)`.
    static func stroke(for lineStyle: String?) -> (width: Double, dash: [Double]) {
        switch lineStyle?.lowercased().replacingOccurrences(of: "()", with: "") {
        case "dashedline", "dashed": return (1, [6, 4])
        case "dottedline", "dotted": return (1, [2, 3])
        case "boldline", "bold": return (2.5, [])
        default: return (1, [])
        }
    }
}

/// The path of one relationship and points along it.
private struct RelationshipGeometry {
    var route: [Point]
    /// The clipped straight chord between the outlines.
    var start: Point
    var end: Point
    var bow: Point

    init(from a: Point, to b: Point, offset: Double, isLoop: Bool, loopBox: Rect, source: [Point], target: [Point]) {
        if isLoop {
            let x = loopBox.maxX + 36, y = loopBox.midY
            route = [a, Point(x, y - loopBox.height / 3), Point(x, y + loopBox.height / 3), b]
            start = Point(x, y)
            end = start
            bow = .zero
            return
        }
        let direction = (b - a).normalized
        let normal = Point(-direction.y, direction.x)
        let chord = EdgeGeometry.clip([a, b], source: source, target: target)
        start = chord.first ?? a
        end = chord.last ?? b
        bow = normal * offset
        route = offset == 0 ? [a, b] : [a, (start + end) * 0.5 + bow * 1.5, b]
    }

    /// A point on the (possibly bowed) path at fraction `t` of the chord.
    func point(at t: Double) -> Point {
        start.interpolated(to: end, t) + bow * (4 * t * (1 - t))
    }

    /// Whether the path passes through any of `frames`.
    func crosses(_ frames: [Rect]) -> Bool {
        guard bow != .zero || start != end else { return false }
        let samples = stride(from: 0.04, through: 0.96, by: 0.04).map(point(at:))
        return frames.contains { frame in
            let inner = frame.insetBy(dx: 4, dy: 4)
            return samples.contains(where: inner.contains)
                || zip(samples, samples.dropFirst()).contains { EdgeGeometry.intersection(from: $0, to: $1, polygon: EdgeGeometry.rectOutline(inner)) != nil }
        }
    }

    /// Label positions to try, from the middle outward.
    func labelCandidates() -> [Point] {
        [0.5, 0.4, 0.6, 0.3, 0.7, 0.22, 0.78].map(point(at:))
    }
}

/// A relationship's label, `[technology]`, and description, stacked.
private struct RelationshipLabel {
    var lines: [TextBlock] = []
    var size = Size.zero

    init(_ rel: C4Diagram.Relationship, number: Int?, palette: C4Palette, measurer: any TextMeasurer) {
        let label = number.map { "\($0): \(rel.label)" } ?? rel.label
        let parts: [(String, Font)] = [
            (label, palette.font("message")),
            (rel.technology.isEmpty ? "" : "[\(rel.technology)]", palette.font("message", delta: -1, italic: true)),
            (rel.description, palette.font("message", delta: -1)),
        ]
        for (text, font) in parts where !text.isEmpty {
            lines.append(TextBlock(LabelParser.parse(text), font: font, measurer: measurer,
                                   maxWidth: palette.wrap ? 180 : nil, forceWrap: palette.wrap))
        }
        size = Size(lines.map(\.width).max() ?? 0, lines.map(\.height).reduce(0, +))
    }

    func items(centeredAt center: Point, color: Color, background: Color, id: String) -> SceneItem {
        let frame = Rect(center: center, size: size)
        var items: [SceneItem] = [.shape(ShapeItem(.rect(frame.insetBy(dx: -3, dy: -1), cornerRadius: 2),
                                                   fill: background.withAlpha(0.85)))]
        var y = frame.minY
        for block in lines {
            items.append(.text(TextItem(block, frame: Rect(x: frame.minX, y: y, width: frame.width, height: block.height),
                                        alignment: .center, color: color)))
            y += block.height
        }
        return .group(GroupItem(id: id, role: "c4-relationship-label", items: items))
    }
}
