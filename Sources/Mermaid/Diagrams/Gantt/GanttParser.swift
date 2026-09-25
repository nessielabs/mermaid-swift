/// Parses gantt source into a `GanttDiagram`.
///
/// The grammar is line oriented: keyword statements (`dateFormat`,
/// `excludes`, `section`, ...), `click` statements, and tasks written as
/// `name : tags, id, start, end`. Keywords are case-insensitive, as in
/// mermaid.js.
struct GanttParser {
    var diagram = GanttDiagram()
    private var currentSection = ""
    private var generatedIDs = 0

    static func parse(_ source: DiagramSource, today: CivilDateTime? = nil) throws -> GanttDiagram {
        var parser = GanttParser()
        parser.diagram.accessibility = source.accessibility
        for line in source.lines {
            try parser.statement(line)
        }
        return parser.diagram
    }

    /// Keywords whose value runs to the end of the line.
    private static let lineKeywords: Set<String> = ["title", "section", "accdescription"]
    /// Keywords whose value stops at `#` or `;`, as in mermaid's lexer.
    private static let valueKeywords: Set<String> = [
        "dateformat", "axisformat", "tickinterval", "includes", "excludes", "todaymarker", "weekday", "weekend", "click",
    ]

    private mutating func statement(_ line: SourceLine) throws {
        let keyword = String(line.text.prefix { !$0.isWhitespace }).lowercased()
        let rest = String(line.text.dropFirst(keyword.count))
        let hasArgument = rest.first?.isWhitespace == true && !rest.trimmingWhitespace().isEmpty

        if Self.lineKeywords.contains(keyword), hasArgument {
            try lineStatement(keyword, rest.trimmingWhitespace())
        } else if Self.valueKeywords.contains(keyword), hasArgument {
            // `todayMarker` styles may contain `#` colors.
            let value = String(rest.prefix { $0 != ";" && ($0 != "#" || keyword == "todaymarker") }).trimmingWhitespace()
            try valueStatement(keyword, value, line)
        } else if keyword == "inclusiveenddates" {
            diagram.inclusiveEndDates = true
        } else if keyword == "topaxis" {
            diagram.topAxis = true
        } else {
            try task(line)
        }
    }

    private mutating func lineStatement(_ keyword: String, _ value: String) throws {
        switch keyword {
        case "title": diagram.title = value
        case "section":
            currentSection = value
            diagram.sections.append(value)
        default: diagram.accessibility.description = value
        }
    }

    private mutating func valueStatement(_ keyword: String, _ value: String, _ line: SourceLine) throws {
        switch keyword {
        case "dateformat": diagram.dateFormat = value
        case "axisformat": diagram.axisFormat = value
        case "tickinterval": diagram.tickInterval = value
        case "todaymarker": diagram.todayMarker = value
        case "includes": diagram.includes = Self.merge(diagram.includes, value)
        case "excludes": diagram.excludes = Self.merge(diagram.excludes, value)
        case "weekday":
            guard let day = GanttDiagram.Weekday(rawValue: value.lowercased()) else {
                throw MermaidError.syntax("Unknown weekday '\(value)'", at: line.location(atOffset: 8))
            }
            diagram.weekday = day
        case "weekend":
            guard let day = GanttDiagram.WeekendStart(rawValue: value.lowercased()) else {
                throw MermaidError.syntax("A weekend starts on 'friday' or 'saturday', not '\(value)'",
                                          at: line.location(atOffset: 8))
            }
            diagram.weekend = day
        default: click(value)
        }
    }

    /// Adds whitespace- or comma-separated tokens, lowercased and deduplicated.
    static func merge(_ existing: [String], _ text: String) -> [String] {
        var result = existing
        for token in text.lowercased().split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "," }) {
            let value = String(token)
            if !result.contains(value) { result.append(value) }
        }
        return result
    }

    /// `click ids [href "url"] [call name(args)]`, in either order.
    private mutating func click(_ text: String) {
        let ids = String(text.prefix { !$0.isWhitespace })
        let rest = String(text.dropFirst(ids.count))
        var link: String?
        var callback: String?
        if let range = rest.range(of: "href") {
            let after = rest[range.upperBound...].trimmingWhitespace()
            if after.hasPrefix("\""), let close = after.dropFirst().firstIndex(of: "\"") {
                link = String(after[after.index(after: after.startIndex)..<close])
            }
        }
        if let range = rest.range(of: "call") {
            let after = rest[range.upperBound...].trimmingWhitespace()
            let name = after.prefix { $0 != "(" && !$0.isWhitespace }
            if !name.isEmpty { callback = String(name) }
        }
        for id in ids.split(separator: ",").map(String.init) {
            guard let i = diagram.tasks.firstIndex(where: { $0.id == id }) else { continue }
            if let link { diagram.tasks[i].link = link }
            if let callback { diagram.tasks[i].callback = callback }
        }
    }

    // MARK: - Tasks

    private mutating func task(_ line: SourceLine) throws {
        guard let colon = line.text.firstIndex(of: ":") else {
            throw MermaidError.syntax("Expected a task written as 'name : details', found '\(line.text)'", at: line.location)
        }
        let name = line.text[..<colon].trimmingWhitespace()
        let dataOffset = line.text.distance(from: line.text.startIndex, to: colon) + 1
        // mermaid's lexer ends task data at `#` or `;`; a trailing `%%`
        // comment is dropped too.
        var data = String(line.text[line.text.index(after: colon)...].prefix { $0 != "#" && $0 != ";" })
        if let comment = data.range(of: "%%") { data = String(data[..<comment.lowerBound]) }
        let location = line.location(atOffset: dataOffset)
        guard !name.isEmpty else {
            throw MermaidError.syntax("Task is missing a name", at: line.location)
        }

        var items = data.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingWhitespace() }
        var tags: Set<GanttDiagram.Tag> = []
        while let first = items.first, let tag = GanttDiagram.Tag(rawValue: first) {
            tags.insert(tag)
            items.removeFirst()
        }
        if items.count == 1, items[0].isEmpty { items = [] }
        guard !items.isEmpty else {
            throw MermaidError.syntax("Task '\(name)' needs an end date or a duration", at: location)
        }
        guard items.count <= 3 else {
            throw MermaidError.syntax("Task '\(name)' has too many details; expected 'id, start, end' at most", at: location)
        }
        if let blank = items.firstIndex(where: \.isEmpty) {
            throw MermaidError.syntax("Task '\(name)' has an empty detail at position \(blank + 1)", at: location)
        }

        let id: String
        if items.count == 3 {
            id = items[0]
        } else {
            generatedIDs += 1
            id = "task\(generatedIDs)"
        }
        let start: GanttDiagram.Task.Start
        switch items.count {
        case 1: start = .previousTaskEnd
        default:
            let text = items[items.count - 2]
            if let ids = Self.references(text, keyword: "after") {
                start = .after(ids)
            } else {
                start = .date(text)
            }
        }
        let endText = items[items.count - 1]
        let end: GanttDiagram.Task.End = Self.references(endText, keyword: "until").map { .until($0) } ?? .dateOrDuration(endText)
        diagram.tasks.append(GanttDiagram.Task(name: name, id: id, section: currentSection, tags: tags,
                                               start: start, end: end, location: location))
    }

    /// The ids in `after a b` or `until a b`, or nil for other text.
    static func references(_ text: String, keyword: String) -> [String]? {
        guard text.lowercased().hasPrefix(keyword), let next = text.dropFirst(keyword.count).first,
              next.isWhitespace else { return nil }
        let ids = text.dropFirst(keyword.count).split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return ids.isEmpty ? nil : ids
    }
}
