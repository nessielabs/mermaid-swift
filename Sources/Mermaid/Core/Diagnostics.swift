/// A position inside Mermaid source text, using 1-based lines and columns.
public struct SourceLocation: Hashable, Sendable, CustomStringConvertible {
    public var line: Int
    public var column: Int

    public init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    public static let start = SourceLocation(line: 1, column: 1)

    public var description: String { "\(line):\(column)" }
}

/// An error raised while parsing or rendering a Mermaid diagram.
///
/// Every parse error carries the location of the offending text so that
/// editors and previews can point the author at the exact problem.
public struct MermaidError: Error, Hashable, Sendable, CustomStringConvertible {
    public enum Kind: Hashable, Sendable {
        /// The source contained no diagram declaration.
        case emptyDiagram
        /// The first statement did not name a known diagram type.
        case unknownDiagramType(String)
        /// A statement could not be parsed.
        case syntax
        /// A statement parsed but is semantically invalid (for example, an
        /// undefined reference).
        case semantic
        /// The front matter or an `%%{init}%%` directive was malformed.
        case configuration
    }

    public var kind: Kind
    public var message: String
    public var location: SourceLocation?

    public init(_ kind: Kind, _ message: String, at location: SourceLocation? = nil) {
        self.kind = kind
        self.message = message
        self.location = location
    }

    static func syntax(_ message: String, at location: SourceLocation) -> MermaidError {
        MermaidError(.syntax, message, at: location)
    }

    static func semantic(_ message: String, at location: SourceLocation? = nil) -> MermaidError {
        MermaidError(.semantic, message, at: location)
    }

    public var description: String {
        guard let location else { return message }
        return "\(location): \(message)"
    }
}
