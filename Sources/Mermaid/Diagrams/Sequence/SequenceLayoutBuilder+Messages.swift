import Foundation

extension SequenceLayoutBuilder {
    mutating func place(_ message: Diagram.Message) {
        guard let a = column[message.from], let b = column[message.to] else { return }
        let label = messageLabel(message)
        y += Self.gapBeforeMessage
        var placed = a == b ? selfMessage(message, label: label) : crossMessage(message, label: label, from: a, to: b)
        if message.showsNumber || settings.showSequenceNumbers {
            let text = self.text(Self.format(message.number), font: Font(family: "sans-serif", size: 11), wrapAt: nil)
            let radius = max(8, text.width / 2 + 3)
            placed.number = (text, placed.start, radius)
            // A tail marker would hide under the badge; start the line past it.
            if message.tail != .none, !message.isSelf {
                placed.start.x += (placed.end.x > placed.start.x ? 1 : -1) * 2 * radius
            }
        }
        layout.messages.append(placed)
        let lineY = placed.end.y
        y = max(y, lineY)
        if message.activatesTarget {
            openActivations[message.to, default: []].append(lineY - 4)
        }
        lastLine = (message.from, message.to, placed.start.y)
        if message.deactivatesSource {
            closeActivation(message.from, at: placed.start.y + 4)
        }
        // The sender's mark goes below its line, clear of the number badge.
        if message.destroysSource { destroy(message.from, at: placed.start.y + (message.isSelf ? 0 : Self.crossSize)) }
        if message.destroysTarget { destroy(message.to, at: lineY) }
    }

    /// A message between two lifelines, with its label above the line.
    mutating func crossMessage(_ message: Diagram.Message, label: TextBlock, from a: Int, to b: Int) -> SequenceLayout.Message {
        if message.createsTarget {
            // Leave room above the line for the upper half of the new head.
            let half = (SequenceLayout.isGlyph(participants[b].kind) ? headHeight(b) : rowHeight) / 2
            y += max(0, half - label.height - Self.labelToLine)
        }
        let lineY = y + label.height + Self.labelToLine
        let right = xs[b] > xs[a]
        let sign: Double = right ? 1 : -1
        let startX = message.centralSource ? xs[a] : edge(message.from, facingRight: right)
        var endX: Double
        if message.createsTarget {
            endX = xs[b] - sign * headHalfWidth(b)
        } else if message.centralTarget {
            endX = xs[b] - sign * Self.dotRadius
        } else if message.destroysTarget {
            endX = xs[b] - sign * Self.crossSize / 2
        } else {
            endX = edge(message.to, facingRight: !right, extra: message.activatesTarget ? 1 : 0)
        }
        let lo = min(startX, endX), hi = max(startX, endX)
        let labelX: Double
        switch settings.messageAlign {
        case .leading: labelX = lo + settings.wrapPadding
        case .trailing: labelX = hi - settings.wrapPadding - label.width
        case .center: labelX = (lo + hi) / 2 - label.width / 2
        }
        var placed = SequenceLayout.Message(
            message: message, start: Point(startX, lineY), end: Point(endX, lineY), loopRight: nil, label: label,
            labelFrame: Rect(x: labelX, y: y, width: label.width, height: label.height), labelAlignment: settings.messageAlign)
        if message.centralSource { placed.dots.append(Point(xs[a], lineY)) }
        if message.centralTarget { placed.dots.append(Point(xs[b], lineY)) }
        if message.createsTarget { create(b, at: lineY) }
        return placed
    }

    /// A message from a lifeline back to itself: a loop to the right with
    /// the label beside it, clear of the lifeline.
    mutating func selfMessage(_ message: Diagram.Message, label: TextBlock) -> SequenceLayout.Message {
        let loopHeight = max(20, label.height + 4)
        let top = y + 2
        let startX = edge(message.from, facingRight: true)
        let endX = edge(message.from, facingRight: true, extra: message.activatesTarget ? 1 : 0)
        let loopRight = max(startX, endX) + Self.selfLoopWidth
        let labelFrame = Rect(x: loopRight + 8, y: top + (loopHeight - label.height) / 2, width: label.width, height: label.height)
        var placed = SequenceLayout.Message(
            message: message, start: Point(startX, top), end: Point(endX, top + loopHeight), loopRight: loopRight,
            label: label, labelFrame: labelFrame, labelAlignment: .leading)
        if message.centralSource || message.centralTarget { placed.dots.append(Point(lifeline(message.from), top)) }
        return placed
    }

    /// Draws a created participant's head centered on its creating message.
    mutating func create(_ i: Int, at lineY: Double) {
        let p = participants[i]
        let height = SequenceLayout.isGlyph(p.kind) ? headHeight(i) : rowHeight
        var head = headFrame(i, top: lineY - height / 2, bottomAligned: false)
        head.size.height = height
        layout.actors.append(.init(id: p.id, kind: p.kind, label: labels[i], x: xs[i], width: widths[i],
                                   head: head, lifelineTop: head.maxY, lifelineBottom: 0))
        y = max(y, head.maxY)
    }

    /// Ends a participant's lifeline, closing any activation it still has.
    mutating func destroy(_ id: String, at lineY: Double) {
        while openActivations[id]?.isEmpty == false { closeActivation(id, at: lineY) }
        guard let i = layout.actors.firstIndex(where: { $0.id == id }) else { return }
        layout.actors[i].isDestroyed = true
        layout.actors[i].lifelineBottom = lineY
        y = max(y, lineY + Self.crossSize / 2)
    }

    /// `1`, `2.5`, `1.25`: autonumber values without trailing zeros.
    static func format(_ number: Double) -> String {
        if number == number.rounded(), abs(number) < 1e15 { return String(Int(number)) }
        var text = String(format: "%.2f", number)
        while text.hasSuffix("0") { text.removeLast() }
        return text
    }
}
