import Foundation

/// A d3-time-format (strftime-style) pattern, the notation of gantt
/// `axisFormat`, rendered in d3's `en-US` locale.
///
/// Every directive d3 documents is supported, including the `-` (no
/// padding), `_` (space padding), and `0` (zero padding) modifiers, as in
/// `%-d` or `%_H`. Unknown directives are emitted verbatim.
struct StrftimeFormat: Hashable, Sendable {
    let pattern: String

    init(_ pattern: String) {
        self.pattern = pattern
    }

    func format(_ date: CivilDateTime) -> String {
        let c = date.components
        var output = ""
        var chars = pattern.makeIterator()
        while let char = chars.next() {
            guard char == "%" else { output.append(char); continue }
            guard var directive = chars.next() else { output.append("%"); break }
            var padding: Character?
            if directive == "-" || directive == "_" || directive == "0" {
                padding = directive
                guard let next = chars.next() else { output.append("%"); output.append(directive); break }
                directive = next
            }
            output += Self.expand(directive, padding: padding, c, date)
        }
        return output
    }

    private static func pad(_ value: Int, _ width: Int, _ fill: Character?, default defaultFill: Character) -> String {
        let fill = fill ?? defaultFill
        let digits = String(value)
        guard fill != "-" else { return digits }
        return String(repeating: fill == "_" ? " " : "0", count: max(0, width - digits.count)) + digits
    }

    private static func expand(_ directive: Character, padding: Character?, _ c: CivilDateTime.Components,
                               _ date: CivilDateTime) -> String {
        let p = { (value: Int, width: Int) in pad(value, width, padding, default: "0") }
        let hour12 = c.hour % 12 == 0 ? 12 : c.hour % 12
        switch directive {
        case "a": return String(DayjsFormat.weekdayNames[c.weekday].prefix(3))
        case "A": return DayjsFormat.weekdayNames[c.weekday]
        case "b", "h": return String(DayjsFormat.monthNames[c.month - 1].prefix(3))
        case "B": return DayjsFormat.monthNames[c.month - 1]
        case "c": return StrftimeFormat("%x, %X").format(date)
        case "d": return p(c.day, 2)
        case "e": return pad(c.day, 2, padding, default: "_")
        case "f": return p(c.millisecond * 1000, 6)
        case "g": return p(((DayjsFormat.isoWeek(c).year % 100) + 100) % 100, 2)
        case "G": return p(DayjsFormat.isoWeek(c).year, 4)
        case "H": return p(c.hour, 2)
        case "I": return p(hour12, 2)
        case "j": return p(c.dayOfYear, 3)
        case "L": return p(c.millisecond, 3)
        case "m": return p(c.month, 2)
        case "M": return p(c.minute, 2)
        case "p": return c.hour < 12 ? "AM" : "PM"
        case "q": return String((c.month - 1) / 3 + 1)
        case "Q": return String(Int(date.milliseconds.rounded(.down)))
        case "s": return String(Int((date.milliseconds / 1000).rounded(.down)))
        case "S": return p(c.second, 2)
        case "u": return String(c.weekday == 0 ? 7 : c.weekday)
        case "U": return p((c.dayOfYear - 1 + 7 - c.weekday) / 7, 2)
        case "V": return p(DayjsFormat.isoWeek(c).week, 2)
        case "w": return String(c.weekday)
        case "W": return p((c.dayOfYear - 1 + 7 - (c.weekday + 6) % 7) / 7, 2)
        case "x": return StrftimeFormat("%-m/%-d/%Y").format(date)
        case "X": return StrftimeFormat("%-I:%M:%S %p").format(date)
        case "y": return p(((c.year % 100) + 100) % 100, 2)
        case "Y": return p(c.year, 4)
        case "Z": return "+0000"
        case "%": return "%"
        default: return "%" + String(directive)
        }
    }
}
