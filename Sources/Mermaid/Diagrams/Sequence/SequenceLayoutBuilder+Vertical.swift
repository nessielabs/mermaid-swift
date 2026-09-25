extension SequenceLayoutBuilder {
    mutating func layoutVertically() {
        let top = rowTop
        for (i, p) in participants.enumerated() where !p.isCreated {
            let head = headFrame(i, top: top, bottomAligned: true)
            layout.actors.append(.init(id: p.id, kind: p.kind, label: labels[i], x: xs[i], width: widths[i],
                                       head: head, lifelineTop: top + rowHeight, lifelineBottom: 0))
        }
        y = top + rowHeight
        place(diagram.statements, depth: 0)
        for id in openActivations.keys.sorted() {
            while openActivations[id]?.isEmpty == false { closeActivation(id, at: y + 4) }
        }
        y += 2 * Self.gapBeforeNote
        var bottom = y
        // Created participants join the list when created; restore column order.
        layout.actors.sort { (column[$0.id] ?? 0) < (column[$1.id] ?? 0) }
        for i in layout.actors.indices where !layout.actors[i].isDestroyed {
            layout.actors[i].lifelineBottom = y
            guard settings.mirrorActors, let c = column[layout.actors[i].id] else { continue }
            let foot = headFrame(c, top: y, bottomAligned: false)
            layout.actors[i].foot = foot
            bottom = max(bottom, foot.maxY)
        }
        placeGroups(bottom: bottom)
    }

    /// Where a participant's head is drawn in a row starting at `top`.
    /// Shapes fill the row; glyphs with labels sit on the row's bottom
    /// edge at the top of the diagram and hang from its top edge below it.
    func headFrame(_ i: Int, top: Double, bottomAligned: Bool) -> Rect {
        guard SequenceLayout.isGlyph(participants[i].kind) else {
            return Rect(x: xs[i] - widths[i] / 2, y: top, width: widths[i], height: rowHeight)
        }
        let height = headHeight(i)
        let width = max(SequenceLayout.glyphSize.width, labels[i].width)
        return Rect(x: xs[i] - width / 2, y: bottomAligned ? top + rowHeight - height : top, width: width, height: height)
    }

    mutating func place(_ statements: [Diagram.Statement], depth: Int) {
        for statement in statements {
            switch statement {
            case .message(let m): place(m)
            case .note(let n): place(n)
            case .activate(let id): activate(id)
            case .deactivate(let id): deactivate(id)
            case .block(let b): place(b, depth: depth)
            }
        }
    }

    // MARK: - Activations

    /// The x of a participant's lifeline, or of the side of its activation
    /// bars facing `right` (with `extra` bars about to open).
    func edge(_ id: String, facingRight right: Bool, extra: Int = 0) -> Double {
        let x = lifeline(id)
        let depth = (openActivations[id]?.count ?? 0) + extra
        guard depth > 0 else { return x }
        let aw = settings.activationWidth
        return right ? x + aw / 2 + Double(depth - 1) * aw / 2 : x - aw / 2
    }

    /// Activations start at the message that caused them, or here.
    mutating func activate(_ id: String) {
        guard column[id] != nil else { return }
        let start = lastLine.flatMap { $0.from == id || $0.to == id ? $0.y - 4 : nil } ?? y
        openActivations[id, default: []].append(start)
    }

    mutating func deactivate(_ id: String) {
        guard openActivations[id]?.isEmpty == false else { return }
        let end = lastLine.flatMap { $0.from == id || $0.to == id ? $0.y + 4 : nil } ?? y
        closeActivation(id, at: end)
    }

    mutating func closeActivation(_ id: String, at end: Double) {
        guard let start = openActivations[id]?.popLast() else { return }
        let depth = openActivations[id]?.count ?? 0
        let bottom = max(end, start + 16)
        y = max(y, bottom)
        let aw = settings.activationWidth
        let x = lifeline(id) - aw / 2 + Double(depth) * aw / 2
        layout.activations.append(.init(participant: id, frame: Rect(x: x, y: start, width: aw, height: bottom - start), depth: depth))
    }

    // MARK: - Notes

    mutating func place(_ note: Diagram.Note) {
        lastLine = nil
        let text = noteText(note)
        let (lo, hi) = noteSpan(note, text: text)
        y += Self.gapBeforeNote
        let frame = Rect(x: lo, y: y, width: hi - lo, height: text.height + 2 * settings.noteMargin)
        layout.notes.append(.init(frame: frame, text: text, alignment: settings.noteAlign))
        y = frame.maxY
    }
}
