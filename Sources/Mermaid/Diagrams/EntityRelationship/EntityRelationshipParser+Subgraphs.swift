extension EntityRelationshipParser {
    /// `subgraph id`, `subgraph id [Title words]`, or `subgraph "Title"`.
    mutating func openSubgraph(at location: SourceLocation) throws {
        scanner.skipWhitespace()
        let header = restOfLine()
        var id = header, title = header
        if let open = header.firstIndex(of: "[") {
            guard header.hasSuffix("]") else {
                throw MermaidError.syntax("Subgraph title is missing its closing ']'", at: location)
            }
            id = String(header[..<open]).trimmingWhitespace()
            title = String(header[header.index(after: open)..<header.index(before: header.endIndex)])
        }
        id = id.unquoted
        title = title.trimmingWhitespace().unquoted
        if id.isEmpty { id = "subGraph\(diagram.subgraphs.count)" }
        let parent = openSubgraphs.last.map { diagram.subgraphs[$0.index].id }
        diagram.subgraphs.append(.init(id: id, title: title, parent: parent))
        openSubgraphs.append(OpenSubgraph(index: diagram.subgraphs.count - 1, location: location))
    }

    /// Closes the innermost subgraph. Entities mentioned inside it join it
    /// unless an inner subgraph (closed earlier) already claimed them, so
    /// each entity belongs to exactly one subgraph.
    mutating func closeSubgraph() {
        guard let open = openSubgraphs.popLast() else { return }
        var members: [String] = []
        for id in open.references where !claimed.contains(id) && !members.contains(id) {
            if diagram.subgraphs.contains(where: { $0.id == id }) { continue }
            members.append(id)
        }
        claimed.formUnion(members)
        diagram.subgraphs[open.index].entities = members
        if !openSubgraphs.isEmpty { openSubgraphs[openSubgraphs.count - 1].references += open.references }
    }

    /// Drops placeholder entities that were really references to
    /// subgraphs (relationships may connect to a whole subgraph).
    mutating func finalize() {
        let subgraphIDs = Set(diagram.subgraphs.map(\.id))
        diagram.entities.removeAll { subgraphIDs.contains($0.name) && !definedEntities.contains($0.name) }
        for i in diagram.subgraphs.indices {
            diagram.subgraphs[i].entities.removeAll { subgraphIDs.contains($0) && !definedEntities.contains($0) }
        }
    }
}
