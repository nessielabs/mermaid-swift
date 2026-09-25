/// Turns a parsed statement tree into a `StateDiagram`, following the
/// scoping rules of mermaid.js:
///
/// - `[*]` is a start state when a transition leaves it and an end state
///   when one enters it. Each composite state (and each concurrency region)
///   has its own start and end, named `<scope>_start` and `<scope>_end`,
///   with `root` as the top-level scope.
/// - A composite body split by `--` becomes one region per part; regions
///   are containers of their own.
/// - States are global by id. A state belongs to the last composite or
///   region that mentions it; mentions at the top level never move a state
///   out of a composite.
/// - `class`, `style` and `click` apply after the whole document is read,
///   creating the state at the top level if it was never mentioned.
struct StateResolver {
    private var diagram = StateDiagram()
    private var index: [String: Int] = [:]
    private var deferred: [StateStatement] = []

    static func resolve(_ document: [StateStatement]) throws -> StateDiagram {
        var resolver = StateResolver()
        try resolver.walk(document, container: nil)
        for statement in resolver.deferred { try resolver.applyDeferred(statement) }
        return resolver.diagram
    }

    // MARK: - Documents

    private mutating func walk(_ document: [StateStatement], container: String?) throws {
        guard let composite = container, diagram.state(composite) != nil,
              document.contains(where: { if case .divider = $0 { true } else { false } }) else {
            for statement in document { try apply(statement, container: container) }
            return
        }
        var parts: [[StateStatement]] = [[]]
        for statement in document {
            if case .divider = statement { parts.append([]) } else { parts[parts.count - 1].append(statement) }
        }
        // A trailing separator does not open an empty region.
        if parts.count > 1, parts.last?.isEmpty == true { parts.removeLast() }
        for part in parts {
            let id = "\(composite)--region-\(diagram.regions.count + 1)"
            diagram.regions.append(.init(id: id, composite: composite))
            try walk(part, container: id)
        }
    }

    private mutating func apply(_ statement: StateStatement, container: String?) throws {
        switch statement {
        case .state(let declaration):
            try declare(declaration, container: container, asSource: true)
        case .relation(let from, let to, let label):
            let source = try mention(from, container: container, asSource: true)
            let target = try mention(to, container: container, asSource: false)
            diagram.transitions.append(.init(from: source, to: target, label: label))
        case .composite(let declaration, let body):
            let id = try declare(declaration, container: container, asSource: true)
            diagram.states[index[id]!].isComposite = true
            try walk(body, container: id)
        case .divider:
            // Dividers are consumed by `walk`; one here has no composite.
            break
        case .note(let target, let position, let text, let alias):
            let targetID = try target.map { try mention($0, container: container, asSource: true) }
            let id = alias ?? "\(targetID ?? "note")----note-\(diagram.notes.count)"
            diagram.notes.append(.init(id: id, target: targetID, position: position, text: text,
                                       parent: targetID == nil ? container : nil))
        case .direction(let direction):
            if let container, let i = index[container] {
                diagram.states[i].direction = direction
            } else if let container, let r = diagram.regions.firstIndex(where: { $0.id == container }) {
                diagram.regions[r].direction = direction
            } else {
                diagram.direction = direction
            }
        case .classDef(let names, let style):
            for name in names {
                diagram.classDefinitions[name] = (diagram.classDefinitions[name] ?? ElementStyle()).overlaid(with: style)
            }
        case .applyClass, .style, .click:
            deferred.append(statement)
        case .hideEmptyDescription:
            diagram.hidesEmptyDescriptions = true
        case .scale(let width):
            diagram.scaleWidth = width
        }
    }

    private mutating func applyDeferred(_ statement: StateStatement) throws {
        switch statement {
        case .applyClass(let ids, let classes, _):
            for id in ids { diagram.states[ensure(id, kind: .state, container: nil)].classes += classes }
        case .style(let ids, let style, _):
            for id in ids {
                let i = ensure(id, kind: .state, container: nil)
                diagram.states[i].style = diagram.states[i].style.overlaid(with: style)
            }
        case .click(let id, let url, let tooltip, _):
            let i = ensure(id, kind: .state, container: nil)
            diagram.states[i].link = url
            diagram.states[i].tooltip = tooltip
        default:
            break
        }
    }

    // MARK: - States

    /// Records a state statement and returns the state's id.
    @discardableResult
    private mutating func declare(_ declaration: StateDeclaration, container: String?, asSource: Bool) throws -> String {
        let id = try mention(declaration.reference, container: container, asSource: asSource)
        let i = index[id]!
        if declaration.kind != .state { diagram.states[i].kind = declaration.kind }
        diagram.states[i].descriptions += declaration.descriptions
        return id
    }

    /// Resolves a reference in `container`, creating or moving the state,
    /// and returns its id. `[*]` resolves to the container's start state
    /// when `asSource` is true and to its end state otherwise.
    private mutating func mention(_ reference: StateReference, container: String?, asSource: Bool) throws -> String {
        let id: String
        let kind: StateDiagram.Kind
        if reference.isTerminal {
            id = "\(container ?? "root")_\(asSource ? "start" : "end")"
            kind = asSource ? .start : .end
        } else {
            id = reference.id
            kind = .state
        }
        if let container, container == id || ancestors(of: container).contains(id) {
            throw MermaidError.semantic("State '\(id)' cannot be inside itself", at: reference.location)
        }
        let i = ensure(id, kind: kind, container: container)
        diagram.states[i].classes += reference.classes
        return id
    }

    private mutating func ensure(_ id: String, kind: StateDiagram.Kind, container: String?) -> Int {
        if let i = index[id] {
            if let container { diagram.states[i].parent = container }
            return i
        }
        diagram.states.append(.init(id: id, kind: kind, parent: container))
        index[id] = diagram.states.count - 1
        return diagram.states.count - 1
    }

    /// The composites and regions enclosing `container`, innermost first,
    /// including `container` itself.
    private func ancestors(of container: String) -> [String] {
        var chain: [String] = []
        var current: String? = container
        while let c = current, !chain.contains(c) {
            chain.append(c)
            current = diagram.region(c)?.composite ?? diagram.state(c)?.parent
        }
        return chain
    }
}
