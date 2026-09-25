/// A parsed user journey (`journey`).
public struct JourneyDiagram: Sendable {
    public static let type = DiagramType.journey

    public struct Task: Hashable, Sendable {
        public var name: String
        /// How the step feels, from 1 (sad) to 5 (happy).
        public var score: Double
        /// The people taking part, in the order written.
        public var actors: [String]
        /// The index into `sections`, or nil before the first section.
        public var section: Int?

        public init(name: String, score: Double, actors: [String] = [], section: Int? = nil) {
            self.name = name
            self.score = score
            self.actors = actors
            self.section = section
        }
    }

    public var title: String?
    /// Section titles in declaration order.
    public var sections: [String] = []
    /// Tasks in declaration order.
    public var tasks: [Task] = []
    public var accessibility = Accessibility()

    public init() {}

    /// Every actor in order of first appearance, which fixes their colors.
    public var actors: [String] {
        var seen: [String] = []
        for actor in tasks.flatMap(\.actors) where !seen.contains(actor) { seen.append(actor) }
        return seen
    }
}
