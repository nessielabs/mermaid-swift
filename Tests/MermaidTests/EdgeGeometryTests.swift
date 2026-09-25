import Testing
@testable import Mermaid

@Suite("Edge geometry")
struct EdgeGeometryTests {
    let box = EdgeGeometry.rectOutline(Rect(x: 100, y: 100, width: 100, height: 100))

    @Test func clipKeepsPortsOnTheOutline() {
        // A route entering through a port on the top edge must end there,
        // not cut from the previous bend to the node's side.
        let route = [Point(0, 0), Point(130, 100), Point(150, 150)]
        let clipped = EdgeGeometry.clip(route, source: nil, target: box)
        #expect(clipped.last == Point(130, 100))
    }

    @Test func clipDropsBendsInsideTheShape() {
        let route = [Point(150, 0), Point(150, 120), Point(150, 150)]
        let clipped = EdgeGeometry.clip(route, source: nil, target: box)
        #expect(clipped == [Point(150, 0), Point(150, 100)])
    }

    @Test func strictInteriorExcludesTheOutline() {
        #expect(EdgeGeometry.strictlyInside(Point(150, 150), box))
        #expect(!EdgeGeometry.strictlyInside(Point(150, 100), box))
        #expect(!EdgeGeometry.strictlyInside(Point(250, 150), box))
    }
}
