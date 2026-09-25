/// Parses the lines of an entity's attribute block (`{ ... }`).
///
/// Each attribute is `type name [keys] ["comment"]`, where keys are `PK`,
/// `FK`, or `UK` separated by commas. Types and names may contain
/// brackets, parentheses, dots, and `*`; `~T~` marks a generic parameter
/// and backticks quote words containing spaces.
enum EntityRelationshipAttributeParser {
    typealias Attribute = EntityRelationshipDiagram.Attribute

    enum Token: Equatable {
        case word(String)
        case comment(String)
        case comma
    }

    static let keyWords: Set<String> = ["PK", "FK", "UK"]

    /// Parses one source line, which normally holds one attribute. Like
    /// mermaid.js, several attributes may share a line.
    ///
    /// Deliberate leniency: a single stray word after an attribute's name
    /// (such as `SK` for a sort key, or a repeated type) is kept as a key
    /// instead of failing, since mermaid.js would silently misread it.
    static func parse(line text: String, at location: SourceLocation) throws -> [Attribute] {
        var tokens = try tokenize(text, at: location)[...]
        var attributes: [Attribute] = []
        while let first = tokens.first {
            guard case .word(let type) = first else {
                throw MermaidError.syntax("Expected an attribute type", at: location)
            }
            tokens.removeFirst()
            guard case .word(let name)? = tokens.first else {
                throw MermaidError.syntax("Attribute '\(type)' is missing a name", at: location)
            }
            tokens.removeFirst()
            var attribute = Attribute(type: type, name: name)
            while let token = tokens.first {
                if token == .comma {
                    tokens.removeFirst()
                } else if case .word(let word) = token, keyWords.contains(word.uppercased()) {
                    attribute.keys.append(word)
                    tokens.removeFirst()
                } else if case .word(let word) = token, strayWord(in: tokens) {
                    attribute.keys.append(word)
                    tokens.removeFirst()
                } else {
                    break
                }
            }
            if case .comment(let comment)? = tokens.first {
                attribute.comment = comment
                tokens.removeFirst()
            }
            attributes.append(attribute)
        }
        return attributes
    }

    /// Whether the word at the front of `tokens` is alone rather than the
    /// type of another attribute (which needs a name word right after it).
    private static func strayWord(in tokens: ArraySlice<Token>) -> Bool {
        let rest = tokens.dropFirst()
        guard case .word? = rest.first else { return true }
        return false
    }

    static func tokenize(_ text: String, at location: SourceLocation) throws -> [Token] {
        var s = Scanner(text, at: location)
        var tokens: [Token] = []
        while true {
            s.skipWhitespace()
            guard let c = s.peek() else { break }
            let start = s.location
            switch c {
            case "\"":
                s.advance()
                guard let comment = s.read(until: "\"") else {
                    throw MermaidError.syntax("Attribute comment is missing its closing '\"'", at: start)
                }
                s.advance()
                tokens.append(.comment(comment))
            case "`":
                s.advance()
                guard let word = s.read(until: "`") else {
                    throw MermaidError.syntax("Attribute word is missing its closing '`'", at: start)
                }
                s.advance()
                tokens.append(.word(word))
            case ",":
                s.advance()
                tokens.append(.comma)
            default:
                tokens.append(.word(genericsResolved(readWord(&s))))
            }
        }
        return tokens
    }

    /// A run of non-space characters. Commas split words except inside
    /// parentheses or brackets, so `decimal(10,2)` stays one type while
    /// `PK,FK` is two keys.
    private static func readWord(_ s: inout Scanner) -> String {
        var word = ""
        var depth = 0
        while let c = s.peek(), c != " ", c != "\t", c != "\"" {
            if c == ",", depth == 0 { break }
            if c == "(" || c == "[" { depth += 1 }
            if c == ")" || c == "]" { depth = max(0, depth - 1) }
            word.append(c)
            s.advance()
        }
        return word
    }

    /// Turns mermaid's generic notation `List~T~` into `List<T>`.
    static func genericsResolved(_ word: String) -> String {
        guard word.filter({ $0 == "~" }).count >= 2 else { return word }
        var result = ""
        var open = true
        for c in word {
            if c == "~" {
                result.append(open ? "<" : ">")
                open.toggle()
            } else {
                result.append(c)
            }
        }
        return result
    }
}
