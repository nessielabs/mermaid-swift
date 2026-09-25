/// A parsed kanban board (`kanban`).
public struct KanbanDiagram: Sendable {
    public static let type = DiagramType.kanban

    /// Task urgency from `@{ priority: '...' }`, drawn as a colored bar.
    public enum Priority: String, CaseIterable, Hashable, Sendable {
        case veryHigh = "Very High", high = "High", medium = "Medium", low = "Low", veryLow = "Very Low"

        /// Matches mermaid's values, ignoring case and extra spaces.
        init?(text: String) {
            let key = text.lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
            guard let match = Self.allCases.first(where: { $0.rawValue.lowercased() == key }) else { return nil }
            self = match
        }
    }

    public struct Item: Hashable, Sendable {
        public var id: String
        /// Raw label text; defaults to the id.
        public var label: String
        public var ticket: String?
        public var assigned: String?
        public var priority: Priority?
        /// An icon name from `::icon(...)` or metadata. Parsed for
        /// compatibility; icon fonts are not drawn.
        public var icon: String?
        /// Classes from a `:::class` line.
        public var classes: [String] = []

        public init(id: String, label: String? = nil) {
            self.id = id
            self.label = label ?? id
        }
    }

    public struct Column: Hashable, Sendable {
        public var id: String
        public var label: String
        public var items: [Item] = []
        public var icon: String?
        public var classes: [String] = []

        public init(id: String, label: String? = nil) {
            self.id = id
            self.label = label ?? id
        }
    }

    /// Columns from left to right.
    public var columns: [Column] = []
    public var accessibility = Accessibility()

    public init() {}
}
