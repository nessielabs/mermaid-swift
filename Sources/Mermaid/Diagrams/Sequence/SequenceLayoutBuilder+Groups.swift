extension SequenceLayoutBuilder {
    /// The columns a `box` spans, from its first to its last visible member.
    func groupColumns(_ box: Diagram.Box) -> ClosedRange<Int>? {
        let members = box.participants.compactMap { column[$0] }
        guard let lo = members.min(), let hi = members.max() else { return nil }
        return lo...hi
    }

    func groupTitle(_ box: Diagram.Box) -> TextBlock? {
        guard let title = box.title, let range = groupColumns(box) else { return nil }
        let natural = baseSpan(range.lowerBound, range.upperBound) + (widths[range.lowerBound] + widths[range.upperBound]) / 2
        let block = text(title, font: settings.messageFont, wrapAt: wraps(box.wrap) ? natural : nil)
        return block.isEmpty ? nil : block
    }

    /// Space between a box's edge and its outermost participants, widened
    /// so the title fits.
    func groupPadding(_ box: Diagram.Box) -> Double {
        guard let range = groupColumns(box) else { return 0 }
        let natural = baseSpan(range.lowerBound, range.upperBound) + (widths[range.lowerBound] + widths[range.upperBound]) / 2
        let needed = (groupTitle(box)?.width ?? 0) + 2 * settings.wrapPadding
        return settings.boxMargin + max(0, needed - natural - 2 * settings.boxMargin) / 2
    }

    /// Keeps neighbouring boxes, and participants next to a box, apart.
    func groupConstraints() -> [(Int, Int, Double)] {
        var padRight = [Double](repeating: 0, count: widths.count)
        var padLeft = [Double](repeating: 0, count: widths.count)
        for box in diagram.boxes {
            guard let range = groupColumns(box) else { continue }
            let pad = groupPadding(box)
            padLeft[range.lowerBound] = max(padLeft[range.lowerBound], pad)
            padRight[range.upperBound] = max(padRight[range.upperBound], pad)
        }
        return widths.indices.dropLast().compactMap { k in
            let pads = padRight[k] + padLeft[k + 1]
            guard pads > 0 else { return nil }
            return (k, k + 1, (widths[k] + widths[k + 1]) / 2 + pads + settings.actorMargin / 2)
        }
    }

    /// The top of the head row: room for box titles when there are boxes.
    var rowTop: Double {
        let boxes = diagram.boxes.filter { groupColumns($0) != nil }
        guard !boxes.isEmpty else { return 0 }
        let titleHeight = boxes.compactMap { groupTitle($0)?.height }.max()
        return titleHeight.map { $0 + 2 * settings.boxTextMargin } ?? settings.boxMargin
    }

    /// Frames every box from the top of the diagram to `bottom`.
    mutating func placeGroups(bottom: Double) {
        for box in diagram.boxes {
            guard let range = groupColumns(box) else { continue }
            let pad = groupPadding(box)
            let left = xs[range.lowerBound] - widths[range.lowerBound] / 2 - pad
            let right = xs[range.upperBound] + widths[range.upperBound] / 2 + pad
            let frame = Rect(x: left, y: 0, width: right - left, height: bottom + settings.boxMargin)
            let title = groupTitle(box)
            let titleFrame = Rect(x: left, y: settings.boxTextMargin, width: frame.width, height: title?.height ?? 0)
            layout.groups.append(.init(frame: frame, title: title, titleFrame: titleFrame, color: box.color))
        }
    }
}
