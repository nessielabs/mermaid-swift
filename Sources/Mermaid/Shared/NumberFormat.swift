import Foundation

/// Formats numbers with d3-format specifiers such as `,`, `.1f`, `$,.2f`,
/// `.0%`, `~s` or `08x`, which Mermaid exposes through settings like
/// `treemap.valueFormat`. Uses the en-US locale, as mermaid.js does.
///
/// Specifier grammar: `[[fill]align][sign][symbol][0][width][,][.precision][~][type]`.
struct NumberFormat: Sendable {
    var fill: Character = " "
    var align: Character = ">"
    var sign: Character = "-"
    var symbol: Character?
    var zero = false
    var width: Int?
    var comma = false
    var precision: Int?
    var trim = false
    var type: Character?

    /// Parses a specifier; returns nil when it is not valid d3-format syntax.
    init?(_ specifier: String) {
        var chars = Array(specifier)
        func take(_ predicate: (Character) -> Bool) -> Character? {
            guard let c = chars.first, predicate(c) else { return nil }
            chars.removeFirst()
            return c
        }
        let aligns: Set<Character> = ["<", ">", "=", "^"]
        if chars.count >= 2, aligns.contains(chars[1]) {
            fill = chars[0]; align = chars[1]; chars.removeFirst(2)
        } else if let a = take({ aligns.contains($0) }) {
            align = a
        }
        if let s = take({ "+-( ".contains($0) }) { sign = s }
        symbol = take { $0 == "$" || $0 == "#" }
        if take({ $0 == "0" }) != nil {
            zero = true
            fill = "0"; align = "="
        }
        var digits = ""
        while let d = take({ $0.isASCII && $0.isNumber }) { digits.append(d) }
        width = Int(digits)
        comma = take { $0 == "," } != nil
        if take({ $0 == "." }) != nil {
            var p = ""
            while let d = take({ $0.isASCII && $0.isNumber }) { p.append(d) }
            guard let value = Int(p) else { return nil }
            precision = value
        }
        trim = take { $0 == "~" } != nil
        type = take { "efgrsp%bodxXcn".contains($0) }
        guard chars.isEmpty else { return nil }
        if type == "n" { comma = true; type = "g" }
    }

    /// A formatter for Mermaid's `valueFormat`, including the currency
    /// shorthands mermaid.js special-cases (`$0,0`, `$,.2f`, `$.1%`), falling
    /// back to thousands separators for anything unrecognized.
    static func mermaidValueFormat(_ specifier: String) -> @Sendable (Double) -> String {
        let spec = specifier.isEmpty ? "," : specifier
        if spec == "$0,0", let f = NumberFormat(",") { return { "$" + f.format($0) } }
        // mermaid.js rebuilds `$,.2f` as `,.2`, dropping the type and printing
        // "1.2e+3"; keeping the author's full specifier gives the documented "1,234.50".
        if spec.hasPrefix("$"), let f = NumberFormat(String(spec.dropFirst())) { return { "$" + f.format($0) } }
        if spec.hasPrefix("$"), spec.contains(",") {
            let precision = spec.range(of: #"\.\d+"#, options: .regularExpression).map { String(spec[$0]) } ?? ""
            if let f = NumberFormat("," + precision) { return { "$" + f.format($0) } }
        }
        let f = NumberFormat(spec) ?? NumberFormat(",")!
        return { f.format($0) }
    }

    func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value < 0 ? "-∞" : "∞") }
        let negative = value < 0 || (value == 0 && value.sign == .minus && type != nil)
        var body = digits(abs(value))
        if trim { body = Self.trimZeros(body) }
        var suffix = ""
        if type == "%" || type == "p" { suffix = "%" }
        if type == "s", let last = body.last, !last.isNumber { suffix = String(last); body.removeLast() }
        if comma { body = Self.group(body) }
        var prefix = ""
        switch symbol {
        case "$": prefix = "$"
        case "#": prefix = ["x": "0x", "X": "0x", "o": "0o", "b": "0b"][type ?? " "] ?? ""
        default: break
        }
        let isNegative = negative && Double(body.filter { $0.isNumber }) != 0
        var signText = ""
        switch sign {
        case "+": signText = isNegative ? "-" : "+"
        case " ": signText = isNegative ? "-" : " "
        case "(": signText = isNegative ? "(" : ""
        default: signText = isNegative ? "−" : ""
        }
        if sign == "(" && isNegative { suffix += ")" }
        return pad(sign: signText + prefix, body: body, suffix: suffix)
    }

    private func digits(_ x: Double) -> String {
        switch type {
        case "f": return String(format: "%.\(precision ?? 6)f", x)
        case "%": return String(format: "%.\(precision ?? 6)f", x * 100)
        case "e": return Self.exponential(x, precision ?? 6)
        case "g": return Self.significant(x, max(1, precision ?? 6))
        case "p": return Self.rounded(x * 100, max(1, precision ?? 6))
        case "r": return Self.rounded(x, max(1, precision ?? 6))
        case "s": return Self.si(x, max(1, precision ?? 6))
        case "d": return String(format: "%.0f", x.rounded())
        case "x", "X", "o", "b":
            let radix = ["x": 16, "X": 16, "o": 8, "b": 2][type!]!
            let text = String(Int64(clamping: Int64(x.rounded().clamped(to: -9.2e18...9.2e18))), radix: radix)
            return type == "X" ? text.uppercased() : text
        case "c": return String(Character(Unicode.Scalar(UInt32(x.clamped(to: 0...0x10FFFF))) ?? " "))
        default:
            if let precision { return Self.trimZeros(Self.significant(x, max(1, precision))) }
            return Self.shortest(x)
        }
    }

    /// The shortest decimal that round-trips, without exponent notation for
    /// ordinary magnitudes (d3's default for an empty type).
    private static func shortest(_ x: Double) -> String {
        if x == x.rounded(), abs(x) < 1e21 { return String(format: "%.0f", x) }
        let text = "\(x)"
        guard text.contains("e") else { return text }
        return trimZeros(String(format: "%.12f", x))
    }

    private static func exponential(_ x: Double, _ p: Int) -> String {
        let text = String(format: "%.\(p)e", x)
        // "1.5e+03" → "1.5e+3", as JavaScript's toExponential prints.
        guard let e = text.firstIndex(of: "e") else { return text }
        let mantissa = text[..<e], exponent = text[text.index(after: e)...]
        let signChar = exponent.first ?? "+"
        let digits = String(exponent.dropFirst().drop { $0 == "0" })
        return "\(mantissa)e\(signChar)\(digits.isEmpty ? "0" : digits)"
    }

    private static func significant(_ x: Double, _ p: Int) -> String {
        guard x != 0 else { return p > 1 ? "0." + String(repeating: "0", count: p - 1) : "0" }
        let exponent = Int(floor(log10(x)))
        if exponent < -7 || exponent >= p { return exponential(x, p - 1) }
        return String(format: "%.\(max(0, p - 1 - exponent))f", x)
    }

    private static func rounded(_ x: Double, _ p: Int) -> String {
        guard x != 0 else { return "0" }
        let exponent = Int(floor(log10(x)))
        return String(format: "%.\(max(0, p - 1 - exponent))f", x)
    }

    private static func si(_ x: Double, _ p: Int) -> String {
        let prefixes = ["y", "z", "a", "f", "p", "n", "µ", "m", "", "k", "M", "G", "T", "P", "E", "Z", "Y"]
        guard x != 0 else { return rounded(0, p) }
        let exponent = Int(floor(log10(x)))
        let group = max(-8, min(8, Int(floor(Double(exponent) / 3))))
        let scaled = x / pow(10, Double(group * 3))
        return rounded(scaled, p) + prefixes[group + 8]
    }

    private static func trimZeros(_ text: String) -> String {
        guard let dot = text.firstIndex(of: ".") else { return text }
        let end = text[dot...].firstIndex { !$0.isNumber && $0 != "." } ?? text.endIndex
        var fraction = String(text[dot..<end])
        while fraction.hasSuffix("0") { fraction.removeLast() }
        if fraction == "." { fraction = "" }
        return String(text[..<dot]) + fraction + String(text[end...])
    }

    private static func group(_ text: String) -> String {
        let integerEnd = text.firstIndex { !$0.isNumber } ?? text.endIndex
        let integer = Array(text[..<integerEnd])
        var grouped = ""
        for (i, c) in integer.enumerated() {
            if i > 0, (integer.count - i) % 3 == 0 { grouped.append(",") }
            grouped.append(c)
        }
        return grouped + text[integerEnd...]
    }

    private func pad(sign: String, body: String, suffix: String) -> String {
        let length = sign.count + body.count + suffix.count
        guard let width, length < width else { return sign + body + suffix }
        let padding = String(repeating: fill, count: width - length)
        switch align {
        case "<": return sign + body + suffix + padding
        case "=": return sign + padding + body + suffix
        case "^":
            let half = padding.count / 2
            return String(padding.prefix(half)) + sign + body + suffix + String(padding.dropFirst(half))
        default: return padding + sign + body + suffix
        }
    }
}
