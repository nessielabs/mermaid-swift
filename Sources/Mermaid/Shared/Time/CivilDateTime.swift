import Foundation

/// A calendar date and time of day without a time zone.
///
/// mermaid.js computes schedules in the viewer's local time zone, so the
/// same gantt chart can shift by a day between machines. MermaidSwift
/// computes them in this zone-free ("floating") time instead: values are
/// milliseconds since 1970-01-01 00:00 on the proleptic Gregorian
/// calendar, days are always 24 hours long, and the result never depends
/// on where the code runs.
public struct CivilDateTime: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// Milliseconds since 1970-01-01T00:00:00.000.
    public var milliseconds: Double

    public init(milliseconds: Double) {
        self.milliseconds = milliseconds
    }

    /// A validated date; returns nil for out-of-range components such as
    /// February 30 or hour 24.
    public init?(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0,
                 second: Int = 0, millisecond: Int = 0) {
        guard (1...12).contains(month), (1...Self.daysInMonth(year: year, month: month)).contains(day),
              (0..<24).contains(hour), (0..<60).contains(minute), (0..<60).contains(second),
              (0..<1000).contains(millisecond) else { return nil }
        self = Self.normalized(year: year, month: month, day: day, hour: hour, minute: minute,
                               second: second, millisecond: millisecond)
    }

    /// The wall-clock time of `date` in `timeZone`.
    public init(_ date: Date, timeZone: TimeZone = .current) {
        let offset = Double(timeZone.secondsFromGMT(for: date))
        milliseconds = ((date.timeIntervalSince1970 + offset) * 1000).rounded()
    }

    /// The current wall-clock time in `timeZone`.
    public static func now(in timeZone: TimeZone = .current) -> CivilDateTime {
        CivilDateTime(Date(), timeZone: timeZone)
    }

    /// Builds a date from components that may overflow their natural
    /// ranges (month 13 is January of the next year, day 0 the last day of
    /// the previous month), the way JavaScript's `Date` constructor does.
    static func normalized(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0,
                           second: Int = 0, millisecond: Double = 0) -> CivilDateTime {
        let monthIndex = month - 1
        let y = year + Int((Double(monthIndex) / 12).rounded(.down))
        let m = ((monthIndex % 12) + 12) % 12 + 1
        let days = Self.days(year: y, month: m, day: 1) + day - 1
        let ms = Double(days) * Self.msPerDay + Double(hour) * 3_600_000 + Double(minute) * 60_000
            + Double(second) * 1000 + millisecond
        return CivilDateTime(milliseconds: ms)
    }

    static func normalized(year: Int, month: Int, day: Int, hour: Int = 0, minute: Int = 0,
                           second: Int = 0, millisecond: Int) -> CivilDateTime {
        normalized(year: year, month: month, day: day, hour: hour, minute: minute, second: second,
                   millisecond: Double(millisecond))
    }

    public static func < (a: CivilDateTime, b: CivilDateTime) -> Bool { a.milliseconds < b.milliseconds }

    /// ISO 8601 without a zone, such as `2024-01-05T09:30:00.000`.
    public var description: String {
        let c = components
        return String(format: "%04d-%02d-%02dT%02d:%02d:%02d.%03d", c.year, c.month, c.day, c.hour, c.minute,
                      c.second, c.millisecond)
    }

    static let msPerDay = 86_400_000.0
}

// MARK: - Components

extension CivilDateTime {
    public struct Components: Hashable, Sendable {
        public var year: Int
        /// 1...12
        public var month: Int
        /// 1...31
        public var day: Int
        public var hour: Int
        public var minute: Int
        public var second: Int
        public var millisecond: Int
        /// 0 is Sunday, 6 is Saturday.
        public var weekday: Int
        /// 1-based day of the year.
        public var dayOfYear: Int
    }

    /// Whole days since 1970-01-01 (negative before it).
    var dayNumber: Int { Int((milliseconds / Self.msPerDay).rounded(.down)) }

    public var components: Components {
        let days = dayNumber
        var rest = Int((milliseconds - Double(days) * Self.msPerDay).rounded(.down))
        let (y, m, d) = Self.civil(days: days)
        let hour = rest / 3_600_000
        rest %= 3_600_000
        let minute = rest / 60_000
        rest %= 60_000
        return Components(year: y, month: m, day: d, hour: hour, minute: minute, second: rest / 1000,
                          millisecond: rest % 1000, weekday: ((days % 7) + 11) % 7,
                          dayOfYear: days - Self.days(year: y, month: 1, day: 1) + 1)
    }

    /// Midnight at the start of this date.
    public var startOfDay: CivilDateTime { CivilDateTime(milliseconds: Double(dayNumber) * Self.msPerDay) }

    static func isLeapYear(_ year: Int) -> Bool { (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 }

    static func daysInMonth(year: Int, month: Int) -> Int {
        switch month {
        case 2: return isLeapYear(year) ? 29 : 28
        case 4, 6, 9, 11: return 30
        default: return 31
        }
    }

    /// Days since 1970-01-01 for a valid civil date (Howard Hinnant's
    /// `days_from_civil`).
    static func days(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// The civil date for days since 1970-01-01 (`civil_from_days`).
    static func civil(days: Int) -> (year: Int, month: Int, day: Int) {
        let z = days + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }
}

// MARK: - Arithmetic

extension CivilDateTime {
    /// A unit of calendar arithmetic.
    public enum Unit: String, CaseIterable, Sendable {
        case millisecond, second, minute, hour, day, week, month, year

        /// The nominal length of the unit in milliseconds.
        var nominalMilliseconds: Double {
            switch self {
            case .millisecond: return 1
            case .second: return 1000
            case .minute: return 60_000
            case .hour: return 3_600_000
            case .day: return CivilDateTime.msPerDay
            case .week: return 7 * CivilDateTime.msPerDay
            case .month: return 30 * CivilDateTime.msPerDay
            case .year: return 365 * CivilDateTime.msPerDay
            }
        }
    }

    /// Adds `amount` of `unit` with dayjs semantics, which gantt durations
    /// follow: sub-day units add exact time, days and weeks round to whole
    /// days, months truncate to whole months, years round to whole years,
    /// and month or year steps clamp the day to the target month's length
    /// (January 31 plus one month is February 28 or 29).
    public func adding(_ amount: Double, _ unit: Unit) -> CivilDateTime {
        guard amount.isFinite else { return self }
        switch unit {
        case .millisecond, .second, .minute, .hour:
            return CivilDateTime(milliseconds: milliseconds + amount * unit.nominalMilliseconds)
        case .day:
            return CivilDateTime(milliseconds: milliseconds + Self.jsRound(amount) * Self.msPerDay)
        case .week:
            return CivilDateTime(milliseconds: milliseconds + Self.jsRound(amount * 7) * Self.msPerDay)
        case .month:
            return addingMonths(Int(amount.rounded(.towardZero)))
        case .year:
            return addingMonths(Int(Self.jsRound(amount)) * 12)
        }
    }

    private func addingMonths(_ months: Int) -> CivilDateTime {
        guard months != 0 else { return self }
        let c = components
        let total = c.year * 12 + (c.month - 1) + months
        let year = Int((Double(total) / 12).rounded(.down))
        let month = total - year * 12 + 1
        let day = min(c.day, Self.daysInMonth(year: year, month: month))
        let timeOfDay = milliseconds - Double(dayNumber) * Self.msPerDay
        return CivilDateTime(milliseconds: Double(Self.days(year: year, month: month, day: day)) * Self.msPerDay + timeOfDay)
    }

    /// JavaScript's `Math.round`: halves round toward positive infinity.
    static func jsRound(_ value: Double) -> Double { (value + 0.5).rounded(.down) }
}
