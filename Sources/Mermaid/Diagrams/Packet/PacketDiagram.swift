/// A parsed packet diagram (`packet` / `packet-beta`): a contiguous run of
/// bit fields, drawn as rows of fixed-width bit cells.
public struct PacketDiagram: Sendable {
    public static let type = DiagramType.packet

    /// A field covering bits `start...end`, inclusive.
    public struct Field: Hashable, Sendable {
        public var start: Int
        public var end: Int
        public var label: String

        public init(start: Int, end: Int, label: String) {
            self.start = start
            self.end = end
            self.label = label
        }

        public var bitCount: Int { end - start + 1 }
    }

    /// A field's share of one row, after splitting at row boundaries.
    public struct Segment: Hashable, Sendable {
        public var start: Int
        public var end: Int
        public var label: String
        /// The index of the field this segment belongs to.
        public var field: Int

        public var bitCount: Int { end - start + 1 }
    }

    /// Fields in declaration order; each starts right after the previous one.
    public var fields: [Field] = []
    /// A `title` statement in the body; the front matter title is used otherwise.
    public var title: String?
    public var accessibility = Accessibility()

    public init() {}

    /// The total number of bits the fields cover.
    public var bitCount: Int { (fields.last?.end ?? -1) + 1 }

    /// Mermaid's cap on rows, which keeps a runaway range such as `0-99999999`
    /// from producing an unbounded drawing.
    public static let maximumRows = 10_000

    /// Splits fields into rows of `bitsPerRow` bits. A field crossing a row
    /// boundary continues on the next row under the same label, as in mermaid.js.
    public func rows(bitsPerRow: Int) -> [[Segment]] {
        let width = max(1, bitsPerRow)
        var rows: [[Segment]] = []
        var current: [Segment] = []
        var row = 0
        for (index, field) in fields.enumerated() {
            var start = field.start
            while start <= field.end, rows.count < Self.maximumRows {
                if start / width != row {
                    if !current.isEmpty { rows.append(current) }
                    current = []
                    row = start / width
                }
                let end = min(field.end, (row + 1) * width - 1)
                current.append(Segment(start: start, end: end, label: field.label, field: index))
                start = end + 1
            }
        }
        if !current.isEmpty, rows.count < Self.maximumRows { rows.append(current) }
        return rows
    }
}
