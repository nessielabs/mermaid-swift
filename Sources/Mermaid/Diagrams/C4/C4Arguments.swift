/// The argument list of a C4 macro call such as
/// `Container(api, "API", $techn="Go", "Serves requests")`.
///
/// Arguments are positional or named (`$name="value"`), as in C4-PlantUML.
/// A named argument sets its own field wherever it appears; like mermaid.js,
/// it still occupies a slot, so positional arguments after it keep their
/// written positions.
struct C4Arguments: Sendable {
    enum Argument: Hashable, Sendable {
        case positional(String)
        case named(String, String)
    }

    var arguments: [Argument]
    /// Where the opening parenthesis was.
    var location: SourceLocation

    /// Resolves arguments against a macro signature: the n-th positional
    /// argument fills `signature[n]` and named arguments fill their own key.
    /// Extra positional arguments are ignored, as mermaid.js does.
    func values(for signature: [String]) -> [String: String] {
        var values: [String: String] = [:]
        var position = 0
        for argument in arguments {
            switch argument {
            case .positional(let value):
                if position < signature.count, !value.isEmpty {
                    values[signature[position]] = value
                }
                position += 1
            case .named(let key, let value):
                values[key] = value
                position += 1
            }
        }
        return values
    }

    /// Reads `( ... )` at the scanner, which must be on the `(`.
    ///
    /// Each argument is a double-quoted string (which may span lines), a
    /// `$name="value"` pair, or bare text up to the next `,` or `)`. Empty
    /// arguments (`,,` or `""`) are kept so later positions stay aligned.
    static func scan(_ scanner: inout Scanner) throws -> C4Arguments {
        let location = scanner.location
        try scanner.expect("(", "Expected '('")
        var arguments: [Argument] = []
        while true {
            scanner.skipWhitespace(newlines: true)
            if scanner.consume(")") {
                if case .positional("")? = arguments.last, arguments.count == 1 { arguments = [] }
                return C4Arguments(arguments: arguments, location: location)
            }
            arguments.append(try argument(&scanner, callStart: location))
            var probe = scanner
            probe.skipWhitespace(newlines: true)
            if scanner.peek() == "\n" || probe.isAtEnd, probe.peek() != ",", probe.peek() != ")" {
                throw MermaidError.syntax("Missing ')' to close the argument list", at: location)
            }
            scanner = probe
            if scanner.consume(",") {
                // A trailing comma before `)` leaves an empty final argument.
                var probe = scanner
                probe.skipWhitespace(newlines: true)
                if probe.peek() == ")" { arguments.append(.positional("")) }
                continue
            }
            guard scanner.peek() == ")" else {
                if scanner.isAtEnd { throw MermaidError.syntax("Missing ')' to close the argument list", at: location) }
                throw MermaidError.syntax("Expected ',' or ')' but found '\(scanner.peek()!)'", at: scanner.location)
            }
        }
    }

    private static func argument(_ scanner: inout Scanner, callStart: SourceLocation) throws -> Argument {
        if scanner.peek() == "," { return .positional("") }
        if scanner.peek() == "$" {
            let start = scanner.location
            scanner.advance()
            let key = scanner.read { $0.isWordCharacter }
            guard !key.isEmpty else { throw MermaidError.syntax("Expected a parameter name after '$'", at: start) }
            scanner.skipWhitespace()
            try scanner.expect("=", "Expected '=' after '$\(key)'")
            scanner.skipWhitespace()
            return .named(key, try value(&scanner, callStart: callStart))
        }
        return .positional(try value(&scanner, callStart: callStart))
    }

    private static func value(_ scanner: inout Scanner, callStart: SourceLocation) throws -> String {
        if scanner.peek() == "\"" {
            let start = scanner.location
            scanner.advance()
            guard let text = scanner.read(until: "\"") else {
                throw MermaidError.syntax("Unterminated string", at: start)
            }
            scanner.advance()
            return text.trimmingWhitespace()
        }
        let text = scanner.read { $0 != "," && $0 != ")" && $0 != "\n" }
        if scanner.peek() == "\n" || scanner.isAtEnd {
            throw MermaidError.syntax("Missing ')' to close the argument list", at: callStart)
        }
        return text.trimmingWhitespace()
    }
}
