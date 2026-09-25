import Foundation

/// Tick and domain arithmetic for chart axes, matching d3-array's `ticks`
/// and d3-scale's `nice`, which mermaid.js uses for every numeric axis.
///
/// Ticks are computed as integer multiples of a power-of-ten step (1, 2,
/// or 5 times 10ⁿ) and divided rather than multiplied for fractional
/// steps, so values such as 0.3 come out exact instead of
/// 0.30000000000000004.
enum ChartTicks {
    private static let e10 = 50.0.squareRoot(), e5 = 10.0.squareRoot(), e2 = 2.0.squareRoot()

    /// (first index, last index, increment). A negative increment means
    /// the step is `1 / -increment`.
    private static func spec(_ start: Double, _ stop: Double, _ count: Double) -> (Double, Double, Double) {
        let step = (stop - start) / max(0, count)
        let power = floor(log10(step))
        let error = step / pow(10, power)
        let factor: Double = error >= e10 ? 10 : error >= e5 ? 5 : error >= e2 ? 2 : 1
        var i1: Double, i2: Double, inc: Double
        if power < 0 {
            inc = pow(10, -power) / factor
            i1 = (start * inc).rounded(.toNearestOrAwayFromZero)
            i2 = (stop * inc).rounded(.toNearestOrAwayFromZero)
            if i1 / inc < start { i1 += 1 }
            if i2 / inc > stop { i2 -= 1 }
            inc = -inc
        } else {
            inc = pow(10, power) * factor
            i1 = (start / inc).rounded(.toNearestOrAwayFromZero)
            i2 = (stop / inc).rounded(.toNearestOrAwayFromZero)
            if i1 * inc < start { i1 += 1 }
            if i2 * inc > stop { i2 -= 1 }
        }
        if i2 < i1, count >= 0.5, count < 2 { return spec(start, stop, count * 2) }
        return (i1, i2, inc)
    }

    /// Roughly `count` evenly spaced, human-friendly values within
    /// `start...stop` (in the direction given).
    static func ticks(_ start: Double, _ stop: Double, count: Int = 10) -> [Double] {
        guard count > 0, start.isFinite, stop.isFinite else { return [] }
        if start == stop { return [start] }
        let reverse = stop < start
        let (i1, i2, inc) = reverse ? spec(stop, start, Double(count)) : spec(start, stop, Double(count))
        guard i2 >= i1, i2 - i1 < 10_000 else { return [] }
        let values = stride(from: i1, through: i2, by: 1).map { i in inc < 0 ? i / -inc : i * inc }
        return reverse ? values.reversed() : values
    }

    /// The tick step as d3 reports it: positive for steps of one or more,
    /// negative reciprocal for fractional steps, zero or NaN when undefined.
    static func increment(_ start: Double, _ stop: Double, count: Int = 10) -> Double {
        spec(start, stop, Double(count)).2
    }

    /// Extends `lower...upper` outward to round tick values, as d3's
    /// `scale.nice()` does.
    static func nice(_ lower: Double, _ upper: Double, count: Int = 10) -> (Double, Double) {
        guard lower.isFinite, upper.isFinite, lower != upper else { return (lower, upper) }
        var start = min(lower, upper), stop = max(lower, upper)
        var previous: Double?
        for _ in 0..<10 {
            let step = increment(start, stop, count: count)
            if step == previous { break }
            if step > 0 {
                start = floor(start / step) * step
                stop = ceil(stop / step) * step
            } else if step < 0 {
                start = ceil(start * step) / step
                stop = floor(stop * step) / step
            } else {
                break
            }
            previous = step
        }
        return lower <= upper ? (start, stop) : (stop, start)
    }
}

/// A linear map from a data domain to a drawing range, like d3's
/// `scaleLinear`.
struct LinearScale: Sendable {
    var domain: (Double, Double)
    var range: (Double, Double)

    init(domain: (Double, Double), range: (Double, Double)) {
        self.domain = domain
        self.range = range
    }

    func callAsFunction(_ value: Double) -> Double {
        let span = domain.1 - domain.0
        // A degenerate domain maps everything to the middle of the range.
        guard span != 0 else { return (range.0 + range.1) / 2 }
        return range.0 + (value - domain.0) / span * (range.1 - range.0)
    }

    func ticks(count: Int = 10) -> [Double] { ChartTicks.ticks(domain.0, domain.1, count: count) }
}

/// Formats numbers the way JavaScript's `String(number)` does for the
/// values charts display: integers without a decimal point and other
/// values in their shortest round-tripping form, without exponents for
/// ordinary magnitudes.
enum ChartNumber {
    static func format(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "NaN" : (value > 0 ? "Infinity" : "-Infinity") }
        if value == 0 { return "0" }
        if value == value.rounded(), abs(value) < 1e21 {
            return String(format: "%.0f", value)
        }
        let text = "\(value)"
        guard let e = text.firstIndex(where: { $0 == "e" || $0 == "E" }) else { return text }
        // Expand exponents between 1e-7 and 1e21, as JavaScript does.
        guard let exponent = Int(text[text.index(after: e)...]), exponent >= -7, exponent < 21 else { return text }
        let negative = value < 0
        let mantissa = text[..<e].replacingOccurrences(of: "-", with: "")
        let digits = mantissa.replacingOccurrences(of: ".", with: "")
        let pointIndex = (mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.startIndex, to: $0) } ?? mantissa.count) + exponent
        var result: String
        if pointIndex <= 0 {
            result = "0." + String(repeating: "0", count: -pointIndex) + digits
        } else if pointIndex >= digits.count {
            result = digits + String(repeating: "0", count: pointIndex - digits.count)
        } else {
            result = String(digits.prefix(pointIndex)) + "." + String(digits.dropFirst(pointIndex))
        }
        return (negative ? "-" : "") + result
    }
}
