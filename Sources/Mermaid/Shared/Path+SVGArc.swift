import Foundation

extension Path {
    /// Appends an SVG elliptical arc (the `A` command, without rotation) from
    /// `start` to `end`, converting endpoint parameters to a center and
    /// sweep as in SVG 1.1 appendix F.6.5. Radii that are too small to span
    /// the endpoints are scaled up, as SVG requires.
    ///
    /// Mermaid draws several shapes (mindmap clouds and bangs) with relative
    /// arc commands; this lets them be reproduced exactly.
    mutating func appendSVGArc(from start: Point, to end: Point, radiusX: Double, radiusY: Double,
                               largeArc: Bool, sweep: Bool) {
        var rx = abs(radiusX), ry = abs(radiusY)
        guard rx > 0, ry > 0, start != end else { line(to: end); return }
        let x1 = (start.x - end.x) / 2, y1 = (start.y - end.y) / 2
        let lambda = x1 * x1 / (rx * rx) + y1 * y1 / (ry * ry)
        if lambda > 1 { rx *= lambda.squareRoot(); ry *= lambda.squareRoot() }
        let numerator = rx * rx * ry * ry - rx * rx * y1 * y1 - ry * ry * x1 * x1
        let denominator = rx * rx * y1 * y1 + ry * ry * x1 * x1
        var coefficient = (max(0, numerator) / denominator).squareRoot()
        if largeArc == sweep { coefficient = -coefficient }
        let cx1 = coefficient * rx * y1 / ry, cy1 = -coefficient * ry * x1 / rx
        let center = Point(cx1 + (start.x + end.x) / 2, cy1 + (start.y + end.y) / 2)
        func angle(_ ux: Double, _ uy: Double) -> Double { atan2(uy, ux) * 180 / .pi }
        let theta = angle((x1 - cx1) / rx, (y1 - cy1) / ry)
        var delta = angle((-x1 - cx1) / rx, (-y1 - cy1) / ry) - theta
        delta = delta.truncatingRemainder(dividingBy: 360)
        if !sweep, delta > 0 { delta -= 360 }
        if sweep, delta < 0 { delta += 360 }
        appendArc(center: center, radiusX: rx, radiusY: ry, from: theta, to: theta + delta, connect: true)
    }
}
