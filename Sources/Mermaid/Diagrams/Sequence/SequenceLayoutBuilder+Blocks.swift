extension SequenceLayoutBuilder {
    /// Space between a frame's edge and what it encloses.
    var framePadding: Double { settings.boxMargin + 2 }
    /// The widest a frame grows to fit its condition on one line before wrapping it.
    var maxConditionWidth: Double { 2 * settings.width }
    var frameFont: Font { settings.messageFont.withSize(max(settings.messageFont.size - 2, 8)) }

    func tag(_ kind: Diagram.BlockKind) -> TextBlock {
        var font = frameFont
        font.bold = true
        return text(kind == .parOver ? "par" : kind.rawValue, font: font, wrapAt: nil)
    }

    func tagSize(_ tag: TextBlock) -> Size {
        Size(max(settings.labelBoxWidth, tag.width + 2 * settings.wrapPadding + 4),
             max(settings.labelBoxHeight, tag.height + 4))
    }

    /// A section condition as mermaid.js shows it, in brackets.
    func condition(_ label: String, wrapAt width: Double?) -> TextBlock? {
        let trimmed = label.trimmingWhitespace()
        guard !trimmed.isEmpty else { return nil }
        return text("[\(trimmed)]", font: frameFont, wrapAt: width)
    }

    // MARK: - Horizontal extent

    /// The x-range a list of statements draws into, or nil if it draws nothing.
    func extent(of statements: [Diagram.Statement]) -> (Double, Double)? {
        var lo = Double.infinity, hi = -Double.infinity
        func include(_ a: Double, _ b: Double) { lo = min(lo, a, b); hi = max(hi, a, b) }
        let reach = settings.activationWidth + 4
        for statement in statements {
            switch statement {
            case .message(let m):
                guard let a = column[m.from], let b = column[m.to] else { continue }
                let label = messageLabel(m)
                if a == b {
                    include(xs[a] - reach, xs[a] + reach + Self.selfLoopWidth + 8 + label.width)
                } else {
                    include(min(xs[a], xs[b]) - reach, max(xs[a], xs[b]) + reach)
                    let mid = (xs[a] + xs[b]) / 2
                    include(mid - label.width / 2, mid + label.width / 2)
                    if m.createsTarget { include(xs[b] - widths[b] / 2, xs[b] + widths[b] / 2) }
                }
            case .note(let n):
                let span = noteSpan(n, text: noteText(n))
                include(span.0, span.1)
            case .block(let b):
                let span = frameSpan(b)
                include(span.0, span.1)
            case .activate, .deactivate:
                continue
            }
        }
        return lo <= hi ? (lo, hi) : nil
    }

    /// The x-range of a block's frame: its contents plus padding, widened
    /// so its tag and conditions fit.
    func frameSpan(_ block: Diagram.Block) -> (Double, Double) {
        let contents = block.sections.compactMap { extent(of: $0.statements) }
        var lo: Double, hi: Double
        if contents.isEmpty {
            lo = (xs.first ?? 0) - framePadding
            hi = (xs.last ?? 0) + framePadding
        } else {
            lo = contents.map(\.0).min()! - framePadding
            hi = contents.map(\.1).max()! + framePadding
        }
        guard block.kind != .rect else { return (lo, hi) }
        var needed = tagSize(tag(block.kind)).width + 2 * framePadding
        if let first = condition(block.sections[0].label, wrapAt: nil) {
            needed += min(first.width, maxConditionWidth)
        }
        for section in block.sections.dropFirst() {
            if let label = condition(section.label, wrapAt: nil) {
                needed = max(needed, min(label.width, maxConditionWidth) + 2 * framePadding)
            }
        }
        hi = max(hi, lo + needed)
        return (lo, hi)
    }

    // MARK: - Vertical placement

    mutating func place(_ block: Diagram.Block, depth: Int) {
        lastLine = nil
        let (lo, hi) = frameSpan(block)
        let width = hi - lo
        y += Self.gapBeforeBlock
        let top = y
        let tag = self.tag(block.kind)
        let tagSize = tagSize(tag)
        let index = layout.frames.count
        var frame = SequenceLayout.Frame(
            kind: block.kind, frame: Rect(x: lo, y: top, width: width, height: 0), depth: depth,
            fill: block.kind == .rect ? block.color : nil, tag: tag,
            tagFrame: Rect(x: lo, y: top, width: tagSize.width, height: tagSize.height),
            condition: nil, conditionFrame: Rect(x: lo, y: top, width: 0, height: 0))
        layout.frames.append(frame)

        if block.kind == .rect {
            y = top + settings.boxMargin
        } else {
            let available = width - tagSize.width - 2 * framePadding
            let natural = condition(block.sections[0].label, wrapAt: nil)
            let condition = (natural?.width ?? 0) > available ? self.condition(block.sections[0].label, wrapAt: available) : natural
            let headerHeight = max(tagSize.height, (condition?.height ?? 0) + 2 * settings.boxTextMargin)
            frame.condition = condition
            frame.conditionFrame = Rect(x: lo + tagSize.width + framePadding, y: top + (headerHeight - (condition?.height ?? 0)) / 2,
                                        width: available, height: condition?.height ?? 0)
            y = top + headerHeight
        }
        for (i, section) in block.sections.enumerated() {
            if i > 0 {
                lastLine = nil
                y += settings.boxMargin
                let label = condition(section.label, wrapAt: width - 2 * framePadding)
                let labelFrame = Rect(x: lo + framePadding, y: y + settings.boxTextMargin,
                                      width: width - 2 * framePadding, height: label?.height ?? 0)
                frame.dividers.append(.init(y: y, label: label, labelFrame: labelFrame))
                y = label == nil ? y : labelFrame.maxY
            }
            place(section.statements, depth: depth + 1)
        }
        lastLine = nil
        y += settings.boxMargin
        frame.frame.size.height = y - top
        layout.frames[index] = frame
    }
}
