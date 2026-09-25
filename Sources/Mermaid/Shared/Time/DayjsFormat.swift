import Foundation

/// A dayjs date format string, the notation of gantt `dateFormat`.
///
/// Formatting covers dayjs' core tokens plus the `advancedFormat` plugin
/// (`Q`, `Do`, `X`, `x`, `k`, `W`); parsing covers the tokens of the
/// `customParseFormat` plugin that mermaid.js loads. Text in `[brackets]`
/// is literal. Parsing is strict like mermaid's `dayjs(text, format,
/// true)`: every field must read back exactly as it would be formatted,
/// so `2024-02-30` and a one-digit month under `MM` are rejected.
struct DayjsFormat: Hashable, Sendable {
    enum Token: Hashable, Sendable {
        case literal(String)
        case field(String)
    }

    let tokens: [Token]

    /// Field tokens, longest first so `YYYY` wins over `YY`.
    static let fields = [
        "YYYY", "YY", "MMMM", "MMM", "MM", "M", "DDDD", "DDD", "Do", "DD", "D", "dddd", "ddd", "dd", "d",
        "HH", "H", "hh", "h", "kk", "k", "mm", "m", "ss", "s", "SSS", "SS", "S", "A", "a", "ZZ", "Z",
        "X", "x", "Q", "WW", "W",
    ]

    init(_ format: String) {
        var tokens: [Token] = []
        var literal = ""
        let chars = Array(format)
        var i = 0
        func flush() {
            if !literal.isEmpty { tokens.append(.literal(literal)); literal = "" }
        }
        outer: while i < chars.count {
            if chars[i] == "[", let close = chars[(i + 1)...].firstIndex(of: "]") {
                literal += String(chars[(i + 1)..<close])
                i = close + 1
                continue
            }
            for field in Self.fields where Self.matches(field, in: chars, at: i) {
                flush()
                tokens.append(.field(field))
                i += field.count
                continue outer
            }
            literal.append(chars[i])
            i += 1
        }
        flush()
        self.tokens = tokens
    }

    private static func matches(_ field: String, in chars: [Character], at index: Int) -> Bool {
        guard index + field.count <= chars.count else { return false }
        return zip(field, chars[index...]).allSatisfy { $0 == $1 }
    }

    /// Whether the format is a bare Unix timestamp (`X` or `x`).
    var isTimestamp: Bool { tokens == [.field("X")] || tokens == [.field("x")] }

    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                             "September", "October", "November", "December"]
    static let weekdayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    static func ordinal(_ n: Int) -> String {
        let tens = n % 100
        if (11...13).contains(tens) { return "\(n)th" }
        switch n % 10 {
        case 1: return "\(n)st"
        case 2: return "\(n)nd"
        case 3: return "\(n)rd"
        default: return "\(n)th"
        }
    }

    static func pad(_ n: Int, _ width: Int) -> String {
        let digits = String(abs(n))
        let padded = String(repeating: "0", count: max(0, width - digits.count)) + digits
        return n < 0 ? "-" + padded : padded
    }
}

// MARK: - Formatting

extension DayjsFormat {
    func format(_ date: CivilDateTime) -> String {
        let c = date.components
        return tokens.map { token in
            switch token {
            case .literal(let text): return text
            case .field(let field): return Self.format(field, c, date)
            }
        }.joined()
    }

    static func format(_ field: String, _ c: CivilDateTime.Components, _ date: CivilDateTime) -> String {
        let hour12 = c.hour % 12 == 0 ? 12 : c.hour % 12
        switch field {
        case "YYYY": return pad(c.year, 4)
        case "YY": return pad(((c.year % 100) + 100) % 100, 2)
        case "MMMM": return monthNames[c.month - 1]
        case "MMM": return String(monthNames[c.month - 1].prefix(3))
        case "MM": return pad(c.month, 2)
        case "M": return String(c.month)
        case "DDDD": return pad(c.dayOfYear, 3)
        case "DDD": return String(c.dayOfYear)
        case "Do": return ordinal(c.day)
        case "DD": return pad(c.day, 2)
        case "D": return String(c.day)
        case "dddd": return weekdayNames[c.weekday]
        case "ddd": return String(weekdayNames[c.weekday].prefix(3))
        case "dd": return String(weekdayNames[c.weekday].prefix(2))
        case "d": return String(c.weekday)
        case "HH": return pad(c.hour, 2)
        case "H": return String(c.hour)
        case "hh": return pad(hour12, 2)
        case "h": return String(hour12)
        case "kk": return pad(c.hour == 0 ? 24 : c.hour, 2)
        case "k": return String(c.hour == 0 ? 24 : c.hour)
        case "mm": return pad(c.minute, 2)
        case "m": return String(c.minute)
        case "ss": return pad(c.second, 2)
        case "s": return String(c.second)
        case "SSS": return pad(c.millisecond, 3)
        case "SS": return pad(c.millisecond / 10, 2)
        case "S": return String(c.millisecond / 100)
        case "A": return c.hour < 12 ? "AM" : "PM"
        case "a": return c.hour < 12 ? "am" : "pm"
        case "ZZ": return "+0000"
        case "Z": return "+00:00"
        case "X": return String(Int((date.milliseconds / 1000).rounded(.down)))
        case "x": return String(Int(date.milliseconds.rounded(.down)))
        case "Q": return String((c.month - 1) / 3 + 1)
        case "WW": return pad(isoWeek(c).week, 2)
        case "W": return String(isoWeek(c).week)
        default: return field
        }
    }

    /// The ISO 8601 week-numbering year and week of a date.
    static func isoWeek(_ c: CivilDateTime.Components) -> (year: Int, week: Int) {
        let isoWeekday = c.weekday == 0 ? 7 : c.weekday
        let week = (c.dayOfYear - isoWeekday + 10) / 7
        if week < 1 { return (c.year - 1, isoWeeks(in: c.year - 1)) }
        if week > isoWeeks(in: c.year) { return (c.year + 1, 1) }
        return (c.year, week)
    }

    /// 53 when the year starts on a Thursday (or a Wednesday in leap
    /// years), otherwise 52.
    static func isoWeeks(in year: Int) -> Int {
        let jan1 = CivilDateTime.normalized(year: year, month: 1, day: 1).components.weekday
        return jan1 == 4 || (jan1 == 3 && CivilDateTime.isLeapYear(year)) ? 53 : 52
    }
}

// MARK: - Parsing

extension DayjsFormat {
    /// Parses `text` strictly. Fields the format omits default like dayjs:
    /// a time without a date falls on `reference`'s date, and a missing
    /// month or day defaults to the first.
    func parse(_ text: String, reference: CivilDateTime) -> CivilDateTime? {
        let chars = Array(text)
        var index = 0
        var matched: [(field: String, text: String)] = []
        var values: [String: Double] = [:]
        var pm: Bool?
        var offsetMinutes = 0.0

        for token in tokens {
            switch token {
            case .literal(let literal):
                for expected in literal {
                    // dayjs treats separator runs loosely only in non-strict
                    // mode; strict parsing requires them verbatim.
                    guard index < chars.count, chars[index] == expected else { return nil }
                    index += 1
                }
            case .field(let field):
                guard let (text, value) = Self.read(field, chars, &index) else { return nil }
                matched.append((field, text))
                switch field {
                case "A", "a": pm = value > 0
                case "Z", "ZZ": offsetMinutes = value
                case "dddd", "ddd", "dd", "d": break
                default: values[field] = value
                }
            }
        }
        guard index == chars.count else { return nil }

        var date: CivilDateTime
        if let seconds = values["X"] {
            date = CivilDateTime(milliseconds: (seconds * 1000).rounded())
        } else if let ms = values["x"] {
            date = CivilDateTime(milliseconds: ms)
        } else {
            let ref = reference.components
            func value(_ keys: String...) -> Double? { keys.lazy.compactMap { values[$0] }.first }
            let year = value("YYYY").map(Int.init) ?? value("YY").map { Int($0) > 68 ? 1900 + Int($0) : 2000 + Int($0) }
            var month = value("MMMM", "MMM", "MM", "M").map(Int.init)
            if month == nil, let quarter = value("Q") { month = (Int(quarter) - 1) * 3 + 1 }
            let dayOfYear = value("DDDD", "DDD").map(Int.init)
            let day = value("Do", "DD", "D").map(Int.init)
            var hour = Int(value("HH", "H", "hh", "h", "kk", "k") ?? 0)
            if value("kk", "k") != nil, hour == 24 { hour = 0 }
            if let pm {
                if pm, hour < 12 { hour += 12 } else if !pm, hour == 12 { hour = 0 }
            }
            let minute = Int(value("mm", "m") ?? 0)
            let second = Int(value("ss", "s") ?? 0)
            let millisecond: Double = value("SSS") ?? value("SS").map { $0 * 10 } ?? value("S").map { $0 * 100 } ?? 0

            let resolvedYear = year ?? ref.year
            let resolvedMonth: Int
            let resolvedDay: Int
            if let dayOfYear {
                resolvedMonth = 1
                resolvedDay = dayOfYear
            } else {
                resolvedMonth = month ?? (year != nil ? 1 : ref.month)
                resolvedDay = day ?? (year == nil && month == nil ? ref.day : 1)
            }
            date = CivilDateTime.normalized(year: resolvedYear, month: resolvedMonth, day: resolvedDay, hour: hour,
                                            minute: minute, second: second, millisecond: millisecond)
        }

        // Strict mode: each field must format back to exactly what was read
        // (in the written zone, before converting to the zone-free result).
        let components = date.components
        for (field, text) in matched where !["Z", "ZZ", "X", "x"].contains(field) {
            let formatted = Self.format(field, components, date)
            let equal = ["A", "a", "MMM", "MMMM", "ddd", "dddd", "dd", "Do"].contains(field)
                ? formatted.lowercased() == text.lowercased() : formatted == text
            guard equal else { return nil }
        }
        date.milliseconds -= offsetMinutes * 60_000
        return date
    }

    /// Reads one field at `index`, returning the matched text and its
    /// numeric value (for names, the 1-based month or 0-based weekday;
    /// for meridiem, 1 for PM; for zones, the offset in minutes).
    private static func read(_ field: String, _ chars: [Character], _ index: inout Int) -> (String, Double)? {
        func digits(_ minCount: Int, _ maxCount: Int, signed: Bool = false, fraction: Bool = false) -> (String, Double)? {
            var end = index
            if signed, end < chars.count, chars[end] == "-" || chars[end] == "+" { end += 1 }
            let start = end
            while end < chars.count, chars[end].isASCII, chars[end].isNumber, end - start < maxCount { end += 1 }
            if fraction, end < chars.count, chars[end] == ".", end + 1 < chars.count, chars[end + 1].isNumber {
                end += 1
                while end < chars.count, chars[end].isASCII, chars[end].isNumber { end += 1 }
            }
            guard end - start >= minCount else { return nil }
            let text = String(chars[index..<end])
            guard let value = Double(text) else { return nil }
            index = end
            return (text, value)
        }
        func name(_ names: [String]) -> (String, Double)? {
            // Longest match first so "June" is not read as "Jun".
            let candidates = names.enumerated().sorted { $0.element.count > $1.element.count }
            for (i, candidate) in candidates {
                let end = index + candidate.count
                guard end <= chars.count, String(chars[index..<end]).lowercased() == candidate.lowercased() else { continue }
                let text = String(chars[index..<end])
                index = end
                return (text, Double(i))
            }
            return nil
        }
        switch field {
        case "YYYY": return digits(4, 4)
        case "YY", "MM", "DD", "HH", "hh", "kk", "mm", "ss", "SS", "WW": return digits(2, 2)
        case "M", "D", "H", "h", "k", "m", "s", "W": return digits(1, 2)
        case "SSS", "DDDD": return digits(3, 3)
        case "DDD": return digits(1, 3)
        case "S", "Q": return digits(1, 1)
        case "Do":
            guard let (text, value) = digits(1, 2) else { return nil }
            let suffixEnd = index + 2
            guard suffixEnd <= chars.count else { return nil }
            let suffix = String(chars[index..<suffixEnd])
            guard ["st", "nd", "rd", "th"].contains(suffix.lowercased()) else { return nil }
            index = suffixEnd
            return (text + suffix, value)
        case "MMMM": return name(monthNames).map { ($0.0, $0.1 + 1) }
        case "MMM": return name(monthNames.map { String($0.prefix(3)) }).map { ($0.0, $0.1 + 1) }
        case "dddd": return name(weekdayNames)
        case "ddd": return name(weekdayNames.map { String($0.prefix(3)) })
        case "dd": return name(weekdayNames.map { String($0.prefix(2)) })
        case "d": return digits(1, 1)
        case "A", "a":
            guard let (text, value) = name(["am", "pm"]) else { return nil }
            return (text, value)
        case "X": return digits(1, 20, signed: true, fraction: true)
        case "x": return digits(1, 20, signed: true)
        case "Z", "ZZ":
            if index < chars.count, chars[index] == "Z" || chars[index] == "z" {
                index += 1
                return ("Z", 0)
            }
            guard index < chars.count, chars[index] == "+" || chars[index] == "-" else { return nil }
            let negative = chars[index] == "-"
            let start = index
            index += 1
            guard let (_, hours) = digits(2, 2) else { index = start; return nil }
            if index < chars.count, chars[index] == ":" { index += 1 }
            guard let (_, minutes) = digits(2, 2) else { index = start; return nil }
            let total = hours * 60 + minutes
            return (String(chars[start..<index]), negative ? -total : total)
        default: return nil
        }
    }
}
