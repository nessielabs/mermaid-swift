/// A parsed timeline (`timeline`, `timeline LR`, `timeline TD`).
public struct TimelineDiagram: Sendable {
    public static let type = DiagramType.timeline

    public enum Direction: String, Hashable, Sendable {
        /// Periods run left to right with events hanging below (default).
        case leftToRight = "LR"
        /// Periods run down a vertical axis with events to the right.
        case topToBottom = "TD"
    }

    /// A time period and the events that happened in it.
    public struct Period: Hashable, Sendable {
        /// Raw label text; may contain `<br>` line breaks.
        public var text: String
        public var events: [String]
        /// The index into `sections`, or nil before the first section.
        public var section: Int?

        public init(text: String, events: [String] = [], section: Int? = nil) {
            self.text = text
            self.events = events
            self.section = section
        }
    }

    public var title: String?
    public var direction = Direction.leftToRight
    /// Section titles in declaration order.
    public var sections: [String] = []
    /// Periods in declaration order.
    public var periods: [Period] = []
    public var accessibility = Accessibility()

    public init() {}
}
