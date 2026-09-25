extension SequenceLayoutBuilder {
    /// Chooses the visible participants and sizes their heads.
    mutating func measureColumns() {
        var visible = diagram.participants
        if settings.hideUnusedParticipants {
            var used: Set<String> = []
            walk(diagram.statements) { statement in
                switch statement {
                case .message(let m): used.formUnion([m.from, m.to])
                case .note(let n):
                    switch n.placement {
                    case .leftOf(let id), .rightOf(let id), .over(let id, nil): used.insert(id)
                    case .over(let a, let b?): used.formUnion([a, b])
                    }
                default: break
                }
            }
            visible.removeAll { !used.contains($0.id) }
        }
        participants = visible
        for (i, p) in visible.enumerated() {
            column[p.id] = i
            let wrapWidth = wraps(p.wrap) ? settings.width - 2 * settings.wrapPadding : nil
            let label = text(p.label, font: settings.actorFont, wrapAt: wrapWidth)
            labels.append(label)
            widths.append(wraps(p.wrap) ? settings.width : max(settings.width, label.width + 2 * settings.wrapPadding))
            rowHeight = max(rowHeight, headHeight(i))
        }
        rowHeight = max(rowHeight, settings.height)
        baseGaps = widths.indices.dropLast().map { (widths[$0] + widths[$0 + 1]) / 2 + settings.actorMargin }
    }

    /// The height of a participant's head: a glyph over its label, or a
    /// shape around it.
    func headHeight(_ i: Int) -> Double {
        if SequenceLayout.isGlyph(participants[i].kind) {
            return SequenceLayout.glyphSize.height + SequenceLayout.glyphGap + labels[i].height
        }
        return labels[i].height + 2 * settings.wrapPadding
    }

    /// Calls `visit` for every statement, depth first.
    func walk(_ statements: [Diagram.Statement], _ visit: (Diagram.Statement) -> Void) {
        for statement in statements {
            visit(statement)
            if case .block(let block) = statement {
                for section in block.sections { walk(section.statements, visit) }
            }
        }
    }

    /// Places lifelines so every constraint between two columns holds.
    ///
    /// Each constraint asks for a minimum distance between two lifelines.
    /// Constraints are applied from the narrowest span to the widest, and
    /// a shortfall is shared evenly by the gaps it spans, so a long label
    /// between distant participants widens the diagram evenly instead of
    /// pushing one pair apart. Gaps only grow, so earlier constraints stay
    /// satisfied.
    mutating func placeColumns() {
        var gaps = baseGaps
        for (a, b, distance) in constraints().sorted(by: { $0.1 - $0.0 < $1.1 - $1.0 }) {
            let current = gaps[a..<b].reduce(0, +)
            guard distance > current else { continue }
            let share = (distance - current) / Double(b - a)
            for k in a..<b { gaps[k] += share }
        }
        xs = []
        var x = widths.first.map { $0 / 2 } ?? 0
        for i in widths.indices {
            xs.append(x)
            if i < gaps.count { x += gaps[i] }
        }
    }

    /// Minimum lifeline distances `(left column, right column, distance)`.
    func constraints() -> [(Int, Int, Double)] {
        var result: [(Int, Int, Double)] = []
        func require(_ a: Int, _ b: Int, _ distance: Double) {
            guard a != b, a >= 0, b >= 0, a < widths.count, b < widths.count else { return }
            result.append((min(a, b), max(a, b), distance))
        }
        let aw = settings.activationWidth, margin = settings.actorMargin
        walk(diagram.statements) { statement in
            switch statement {
            case .message(let m):
                guard let a = column[m.from], let b = column[m.to] else { return }
                let label = messageLabel(m)
                if a == b {
                    let reach = aw + Self.selfLoopWidth + 8 + label.width
                    require(a, a + 1, reach + margin / 2)
                    return
                }
                var distance = label.width + 2 * settings.wrapPadding + aw
                if m.showsNumber || settings.showSequenceNumbers { distance += 24 }
                if m.createsTarget { distance += headHalfWidth(b) }
                require(a, b, distance)
            case .note(let n):
                let width = noteWidth(n, text: noteText(n))
                switch n.placement {
                case .rightOf(let id): if let i = column[id] { require(i, i + 1, width + margin) }
                case .leftOf(let id): if let i = column[id] { require(i - 1, i, width + margin) }
                case .over(let id, nil):
                    if let i = column[id] {
                        require(i - 1, i, width / 2 + margin / 2)
                        require(i, i + 1, width / 2 + margin / 2)
                    }
                case .over(let p, let q?):
                    if let i = column[p], let j = column[q] { require(i, j, width - margin) }
                }
            default:
                break
            }
        }
        result += groupConstraints()
        return result
    }

    /// Half the drawn width of a participant's head, where messages to a
    /// created participant stop.
    func headHalfWidth(_ i: Int) -> Double {
        SequenceLayout.isGlyph(participants[i].kind) ? SequenceLayout.glyphSize.width / 2 : widths[i] / 2
    }
}
