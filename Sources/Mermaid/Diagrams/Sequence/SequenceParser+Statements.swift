import Foundation

extension SequenceParser {
    // MARK: - Blocks

    mutating func openBlock(_ kind: SequenceDiagram.BlockKind, _ text: String, _ s: SequenceStatementText) throws {
        var color: Color?
        var label = text, wrap: Bool?
        if kind == .rect {
            // mermaid.js falls back to a theme color when the color is missing or invalid.
            color = Color(css: text)
            label = ""
        } else {
            (label, wrap) = Self.extractWrap(text)
        }
        let block = SequenceDiagram.Block(kind: kind, sections: [.init(label: label, wrap: wrap)], color: color)
        openBlocks.append(OpenBlock(block: block, location: s.location))
    }

    /// `else`, `and`, or `option`, which start a new section of the enclosing block.
    mutating func section(_ keyword: String, label: String, _ s: SequenceStatementText) throws {
        guard let open = openBlocks.last, open.block.kind.sectionKeyword == keyword else {
            let owner = ["else": "alt", "and": "par", "option": "critical"][keyword] ?? keyword
            throw MermaidError.syntax("'\(keyword)' is only allowed inside a '\(owner)' block", at: s.location)
        }
        let (text, wrap) = Self.extractWrap(label)
        openBlocks[openBlocks.count - 1].block.sections.append(.init(label: text, wrap: wrap))
    }

    mutating func end(_ rest: String, _ s: SequenceStatementText) throws {
        guard rest.isEmpty else {
            throw MermaidError.syntax("Unexpected '\(rest)' after 'end'", at: s.location(at: 3))
        }
        if let box = openBox {
            if diagram.boxes[box.index].participants.isEmpty {
                // An empty box has nothing to enclose.
                diagram.boxes.removeLast()
            }
            openBox = nil
        } else if let open = openBlocks.popLast() {
            append(.block(open.block))
        } else {
            throw MermaidError.syntax("'end' without a matching block", at: s.location)
        }
    }

    // MARK: - Notes

    /// `note left of A: text`, `note right of A: text`, `note over A[, B]: text`.
    mutating func note(_ text: String, _ s: SequenceStatementText, at offset: Int) throws {
        guard let match = text.range(of: #"^(left\s+of|right\s+of|over)\s+"#, options: [.regularExpression, .caseInsensitive]) else {
            throw MermaidError.syntax("Expected 'left of', 'right of' or 'over' after 'note'", at: s.location(at: offset))
        }
        let placementWord = text[match].lowercased().filter(\.isLetter)
        let targetOffset = offset + text.distance(from: text.startIndex, to: match.upperBound)
        guard let (targets, body) = String(text[match.upperBound...]).splitOnce(":") else {
            throw MermaidError.syntax("Expected ':' before the note text", at: s.location(at: targetOffset))
        }
        let names = try targets.split(separator: ",", omittingEmptySubsequences: false)
            .map { try participantName(String($0), s, at: targetOffset) }
        guard names.count == 1 || (names.count == 2 && placementWord == "over") else {
            throw MermaidError.syntax("A note spans at most two participants, and only with 'over'", at: s.location(at: targetOffset))
        }
        names.forEach { ensureParticipant($0) }
        let placement: SequenceDiagram.Note.Placement
        switch placementWord {
        case "leftof": placement = .leftOf(names[0])
        case "rightof": placement = .rightOf(names[0])
        default: placement = .over(names[0], names.count == 2 && names[1] != names[0] ? names[1] : nil)
        }
        let (body_, wrap) = Self.extractWrap(body)
        var note = SequenceDiagram.Note(placement, text: body_)
        note.wrap = wrap
        append(.note(note))
    }

    // MARK: - Numbering and activation

    /// `autonumber`, `autonumber off`, `autonumber <start>`, `autonumber <start> <step>`.
    mutating func autonumber(_ text: String, _ s: SequenceStatementText, at offset: Int) throws {
        let words = text.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        if words.count == 1, words[0].lowercased() == "off" {
            numbering.visible = false
            return
        }
        let numbers = words.map(Double.init)
        guard words.count <= 2, numbers.allSatisfy({ $0 != nil }) else {
            throw MermaidError.syntax("Expected 'autonumber', 'autonumber off', or 'autonumber <start> [step]'", at: s.location(at: offset))
        }
        if let start = numbers.first ?? nil { numbering.next = start }
        numbering.step = numbers.count == 2 ? (numbers[1] ?? 1) : (numbers.isEmpty ? numbering.step : 1)
        numbering.visible = true
    }

    mutating func deactivate(_ id: String, at location: SourceLocation) throws {
        guard activationDepth[id, default: 0] > 0 else {
            throw MermaidError.semantic("Cannot deactivate '\(id)', which is not active", at: location)
        }
        activationDepth[id, default: 0] -= 1
    }

    // MARK: - Messages

    /// `A->>+B: text` and every other arrow form.
    mutating func signal(_ s: SequenceStatementText) throws {
        let (head, rawText) = s.text.splitOnce(":") ?? (s.text, "")
        guard let signal = SequenceArrowScanner.signal(in: head) else {
            throw MermaidError.syntax("Expected a statement or a message such as 'A->>B: text'", at: s.location)
        }
        ensureParticipant(signal.source)
        ensureParticipant(signal.target)
        let (text, wrap) = Self.extractWrap(rawText)
        var message = SequenceDiagram.Message(from: signal.source, to: signal.target, text: text,
                                              line: signal.arrow.line, head: signal.arrow.head, tail: signal.arrow.tail)
        message.wrap = wrap
        message.activatesTarget = signal.activate
        message.deactivatesSource = signal.deactivate
        message.centralSource = signal.centralSource
        message.centralTarget = signal.centralTarget
        if let create = pendingCreate {
            guard create.id == message.to else {
                throw MermaidError.semantic("Created participant '\(create.id)' must receive the message that follows its creation", at: s.location)
            }
            message.createsTarget = true
            pendingCreate = nil
        }
        for destroy in pendingDestroys {
            guard destroy.id == message.from || destroy.id == message.to else {
                throw MermaidError.semantic("Destroyed participant '\(destroy.id)' must send or receive the message that follows", at: s.location)
            }
            if destroy.id == message.from { message.destroysSource = true }
            if destroy.id == message.to { message.destroysTarget = true }
        }
        pendingDestroys = []
        message.number = numbering.next
        message.showsNumber = numbering.visible
        numbering.next = ((numbering.next + numbering.step) * 100).rounded() / 100
        append(.message(message))
        if signal.activate { activationDepth[message.to, default: 0] += 1 }
        if signal.deactivate { try deactivate(message.from, at: s.location(at: signal.arrowOffset + signal.arrow.token.count)) }
    }
}
