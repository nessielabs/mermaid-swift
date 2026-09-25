/// A parsed gantt chart (`gantt`).
///
/// The model keeps tasks as written (start and end specifications are
/// resolved later by `schedule(today:)`), because relative starts such as
/// `after a b` and time-only date formats depend on other tasks and on
/// the current date.
public struct GanttDiagram: Sendable {
    public static let type = DiagramType.gantt

    public enum Tag: String, CaseIterable, Hashable, Sendable {
        case active, done, crit, milestone, vert
    }

    public struct Task: Hashable, Sendable {
        /// How a task's start is specified.
        public enum Start: Hashable, Sendable {
            /// No start given: the task follows the previously declared task.
            case previousTaskEnd
            /// `after id1 id2 ...`: the latest end of the referenced tasks.
            case after([String])
            /// A date in the chart's `dateFormat`.
            case date(String)
        }

        /// How a task's end is specified.
        public enum End: Hashable, Sendable {
            /// `until id1 id2 ...`: the earliest start of the referenced tasks.
            case until([String])
            /// A date in the chart's `dateFormat` or a duration such as `3d`.
            case dateOrDuration(String)
        }

        public var name: String
        /// The declared id, or `task1`, `task2`, ... for tasks without one.
        public var id: String
        /// The section the task belongs to; empty before the first section.
        public var section: String
        public var tags: Set<Tag>
        public var start: Start
        public var end: End
        /// The URL from `click id href "..."`.
        public var link: String?
        /// The callback name from `click id call name(...)`. Parsed for
        /// compatibility; static renderers have nothing to call.
        public var callback: String?
        /// Where the task was declared, for error messages.
        public var location: SourceLocation

        public init(name: String, id: String, section: String = "", tags: Set<Tag> = [],
                    start: Start, end: End, location: SourceLocation = .start) {
            self.name = name
            self.id = id
            self.section = section
            self.tags = tags
            self.start = start
            self.end = end
            self.location = location
        }

        public func has(_ tag: Tag) -> Bool { tags.contains(tag) }
    }

    public enum Weekday: String, CaseIterable, Hashable, Sendable {
        case sunday, monday, tuesday, wednesday, thursday, friday, saturday

        /// 0 is Sunday.
        public var index: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    }

    /// The first day of the two-day weekend excluded by `excludes weekends`.
    public enum WeekendStart: String, Hashable, Sendable {
        case friday, saturday
    }

    public var title: String?
    /// The dayjs format task dates are written in.
    public var dateFormat = "YYYY-MM-DD"
    /// The d3 format of axis labels (`axisFormat`); nil uses configuration.
    public var axisFormat: String?
    /// The axis tick spacing (`tickInterval 1week`); nil picks automatically.
    public var tickInterval: String?
    /// `off`, or CSS declarations styling the today line; empty by default.
    public var todayMarker = ""
    /// Lowercased `excludes` tokens: `weekends`, weekday names, or dates.
    public var excludes: [String] = []
    /// Lowercased `includes` tokens, overriding `excludes`.
    public var includes: [String] = []
    public var inclusiveEndDates = false
    public var topAxis = false
    /// The first day of week-based ticks (`weekday monday`).
    public var weekday: Weekday?
    public var weekend = WeekendStart.saturday
    /// Section names in declaration order.
    public var sections: [String] = []
    /// Tasks in declaration order.
    public var tasks: [Task] = []
    /// The date treated as "today" for the today marker, time-only dates,
    /// and unresolvable references. Nil means the current date in the
    /// local time zone; set it for reproducible output.
    public var today: CivilDateTime?
    public var accessibility = Accessibility()

    public init() {}

    public func task(_ id: String) -> Task? { tasks.first { $0.id == id } }
}
