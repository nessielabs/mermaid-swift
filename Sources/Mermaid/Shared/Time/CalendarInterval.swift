import Foundation

/// A calendar interval such as "every 2 days" or "every week starting
/// Monday", with d3-time semantics. Time axes use intervals to place
/// their ticks on round calendar boundaries.
struct CalendarInterval: Hashable, Sendable {
    enum Unit: Hashable, Sendable {
        case millisecond, second, minute, hour, day
        /// Weeks starting on `firstWeekday` (0 is Sunday).
        case week(firstWeekday: Int)
        case month, year
    }

    var unit: Unit
    /// Only boundaries whose unit field is a multiple of `step` are used,
    /// as with d3's `interval.every(step)`.
    var step: Int

    init(_ unit: Unit, every step: Int = 1) {
        self.unit = unit
        self.step = max(1, step)
    }

    /// Parses a gantt `tickInterval` such as `1day` or `2week`.
    init?(tickInterval text: String, firstWeekday: Int) {
        let digits = text.prefix { $0.isASCII && $0.isNumber }
        guard let count = Int(digits), count > 0, digits.first != "0" else { return nil }
        switch text.dropFirst(digits.count) {
        case "millisecond": self.init(.millisecond, every: count)
        case "second": self.init(.second, every: count)
        case "minute": self.init(.minute, every: count)
        case "hour": self.init(.hour, every: count)
        case "day": self.init(.day, every: count)
        case "week": self.init(.week(firstWeekday: firstWeekday), every: count)
        case "month": self.init(.month, every: count)
        default: return nil
        }
    }

    /// The approximate length of one step, for estimating tick counts.
    var nominalMilliseconds: Double {
        let base: CivilDateTime.Unit
        switch unit {
        case .millisecond: base = .millisecond
        case .second: base = .second
        case .minute: base = .minute
        case .hour: base = .hour
        case .day: base = .day
        case .week: base = .week
        case .month: base = .month
        case .year: base = .year
        }
        return base.nominalMilliseconds * Double(step)
    }

    /// The latest unit boundary at or before `date`.
    func floor(_ date: CivilDateTime) -> CivilDateTime {
        let ms = date.milliseconds
        func floorTo(_ size: Double) -> CivilDateTime { CivilDateTime(milliseconds: (ms / size).rounded(.down) * size) }
        switch unit {
        case .millisecond: return floorTo(Double(step))
        case .second: return floorTo(1000)
        case .minute: return floorTo(60_000)
        case .hour: return floorTo(3_600_000)
        case .day: return date.startOfDay
        case .week(let first):
            let day = date.startOfDay
            let back = (day.components.weekday - first + 7) % 7
            return day.adding(Double(-back), .day)
        case .month:
            let c = date.components
            return CivilDateTime.normalized(year: c.year, month: c.month, day: 1)
        case .year:
            let year = date.components.year
            let floored = Int((Double(year) / Double(step)).rounded(.down)) * step
            return CivilDateTime.normalized(year: floored, month: 1, day: 1)
        }
    }

    /// The boundary one unit after `date` (which must be a boundary).
    private func next(_ date: CivilDateTime) -> CivilDateTime {
        switch unit {
        case .millisecond: return CivilDateTime(milliseconds: date.milliseconds + Double(step))
        case .second: return date.adding(1, .second)
        case .minute: return date.adding(1, .minute)
        case .hour: return date.adding(1, .hour)
        case .day: return date.adding(1, .day)
        case .week: return date.adding(1, .week)
        case .month: return date.adding(1, .month)
        case .year: return date.adding(Double(step), .year)
        }
    }

    /// Whether a boundary belongs to this interval's `every(step)` subset.
    private func accepts(_ date: CivilDateTime) -> Bool {
        guard step > 1 else { return true }
        let c = date.components
        switch unit {
        case .millisecond, .year: return true
        case .second: return c.second % step == 0
        case .minute: return c.minute % step == 0
        case .hour: return c.hour % step == 0
        case .day: return (c.day - 1) % step == 0
        case .month: return (c.month - 1) % step == 0
        case .week:
            // d3 counts weeks from the week containing the epoch.
            let weeks = Int(((floor(date).milliseconds - floor(CivilDateTime(milliseconds: 0)).milliseconds)
                / (7 * CivilDateTime.msPerDay)).rounded())
            return ((weeks % step) + step) % step == 0
        }
    }

    /// Boundaries in `start...stop`, at most `limit` of them.
    func dates(from start: CivilDateTime, through stop: CivilDateTime, limit: Int = 10_000) -> [CivilDateTime] {
        var date = floor(start)
        if date < start { date = next(date) }
        var result: [CivilDateTime] = []
        var guardCount = 0
        while date <= stop, result.count < limit, guardCount < limit * 32 {
            if accepts(date) { result.append(date) }
            date = next(date)
            guardCount += 1
        }
        return result
    }
}

// MARK: - Automatic ticks

extension CalendarInterval {
    /// The interval d3's time scale picks for about `count` ticks across
    /// `start...stop` (`scaleTime().ticks(count)`).
    static func automatic(from start: CivilDateTime, to stop: CivilDateTime, count: Int = 10) -> CalendarInterval {
        let second = 1000.0, minute = 60 * second, hour = 60 * minute, day = 24 * hour
        let week = 7 * day, month = 30 * day, year = 365 * day
        let candidates: [(Unit, Int, Double)] = [
            (.second, 1, second), (.second, 5, 5 * second), (.second, 15, 15 * second), (.second, 30, 30 * second),
            (.minute, 1, minute), (.minute, 5, 5 * minute), (.minute, 15, 15 * minute), (.minute, 30, 30 * minute),
            (.hour, 1, hour), (.hour, 3, 3 * hour), (.hour, 6, 6 * hour), (.hour, 12, 12 * hour),
            (.day, 1, day), (.day, 2, 2 * day), (.week(firstWeekday: 0), 1, week),
            (.month, 1, month), (.month, 3, 3 * month), (.year, 1, year),
        ]
        let span = abs(stop.milliseconds - start.milliseconds)
        let target = span / Double(max(count, 1))
        let i = candidates.firstIndex { $0.2 > target } ?? candidates.count
        if i == candidates.count {
            let step = tickStep(start.milliseconds / year, stop.milliseconds / year, count)
            return CalendarInterval(.year, every: Int(max(1, step.rounded())))
        }
        if i == 0 {
            return CalendarInterval(.millisecond, every: Int(max(1, tickStep(start.milliseconds, stop.milliseconds, count).rounded())))
        }
        let pick = target / candidates[i - 1].2 < candidates[i].2 / target ? candidates[i - 1] : candidates[i]
        return CalendarInterval(pick.0, every: pick.1)
    }

    /// d3-array's `tickStep`: a 1, 2, or 5 multiple of a power of ten.
    static func tickStep(_ start: Double, _ stop: Double, _ count: Int) -> Double {
        let step0 = abs(stop - start) / Double(max(count, 1))
        guard step0 > 0, step0.isFinite else { return 1 }
        var step1 = pow(10, (log10(step0)).rounded(.down))
        let error = step0 / step1
        if error >= 50.squareRoot() { step1 *= 10 } else if error >= 10.squareRoot() { step1 *= 5 } else if error >= 2.squareRoot() { step1 *= 2 }
        return step1
    }
}
