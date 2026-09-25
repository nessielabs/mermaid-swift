/// An attribute or method of a class, parsed the way mermaid.js parses
/// member text: an optional leading visibility, a name, parameters and a
/// return type for methods, and a trailing classifier.
public struct ClassMember: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable { case attribute, method }

    public enum Visibility: String, Hashable, Sendable {
        case none = "", `public` = "+", `private` = "-", protected = "#", package = "~"
    }

    public enum Classifier: String, Hashable, Sendable {
        case none = ""
        /// `$`: drawn underlined.
        case `static` = "$"
        /// `*`: drawn in italics.
        case abstract = "*"
    }

    public var kind: Kind
    public var visibility: Visibility = .none
    /// The attribute text or method name, with generic tildes as written.
    public var name: String
    public var parameters = ""
    public var returnType = ""
    public var classifier: Classifier = .none

    public init(kind: Kind, visibility: Visibility = .none, name: String, parameters: String = "",
                returnType: String = "", classifier: Classifier = .none) {
        self.kind = kind
        self.visibility = visibility
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.classifier = classifier
    }

    /// Parses member text. Text containing `)` after its first character is
    /// a method; anything else is an attribute.
    public init(parsing raw: String) {
        let text = raw.trimmingWhitespace()
        if let close = text.lastIndex(of: ")"), close > text.startIndex {
            self.init(method: text, close: close)
        } else {
            self.init(attribute: text)
        }
    }

    private init(attribute text: String) {
        self.init(kind: .attribute, name: "")
        var body = Substring(text)
        if let first = body.first, let v = Visibility(rawValue: String(first)), v != .none {
            visibility = v
            body = body.dropFirst()
        }
        if let last = body.last, let c = Classifier(rawValue: String(last)), c != .none {
            classifier = c
            body = body.dropLast()
        }
        name = body.trimmingWhitespace()
    }

    /// Mirrors mermaid's `([#+~-])?(.+)\((.*)\)([\s$*])?(.*)`: the name runs
    /// to the last `(` before the last `)`, and a classifier may follow the
    /// `)` directly or end the return type.
    private init(method text: String, close: String.Index) {
        self.init(kind: .method, name: "")
        guard let open = text[..<close].lastIndex(of: "("), open > text.startIndex else {
            self.init(attribute: text)
            return
        }
        var nameStart = text.startIndex
        if let v = Visibility(rawValue: String(text[nameStart])), v != .none,
           text.index(after: nameStart) < open {
            visibility = v
            nameStart = text.index(after: nameStart)
        }
        name = text[nameStart..<open].trimmingWhitespace()
        parameters = text[text.index(after: open)..<close].trimmingWhitespace()
        var rest = text[text.index(after: close)...]
        if let first = rest.first, let c = Classifier(rawValue: String(first)), c != .none {
            classifier = c
            rest = rest.dropFirst()
        }
        returnType = rest.trimmingWhitespace()
        if classifier == .none, let last = returnType.last, let c = Classifier(rawValue: String(last)), c != .none {
            classifier = c
            returnType.removeLast()
            returnType = returnType.trimmingWhitespace()
        }
    }

    /// The text drawn in the class box: visibility, name, parameters in
    /// parentheses and ` : ReturnType`, with generics as angle brackets.
    public var displayText: String {
        var text = visibility.rawValue + ClassGenerics.render(name)
        if kind == .method {
            text += "(" + ClassGenerics.render(parameters) + ")"
            if !returnType.isEmpty { text += " : " + ClassGenerics.render(returnType) }
        }
        return LabelParser.decodeMermaidEntities(text.trimmingWhitespace())
    }
}

/// Mermaid's tilde notation for generics: `List~int~` is `List<int>` and
/// `List~List~int~~` is `List<List<int>>`.
enum ClassGenerics {
    /// Converts tilde pairs to angle brackets, matching mermaid.js'
    /// `parseGenericTypes`: text is processed per comma-separated part (so
    /// `Map~K, V~` stays one generic), pairing the outermost tildes first.
    static func render(_ text: String) -> String {
        guard text.contains("~") else { return text }
        let parts = splitKeepingCommas(text)
        var output: [String] = []
        var i = 0
        while i < parts.count {
            var part = parts[i]
            if part == ",", i > 0, i + 1 < parts.count, shouldCombine(parts[i - 1], parts[i + 1]) {
                part = parts[i - 1] + "," + parts[i + 1]
                output.removeLast()
                i += 1
            }
            output.append(processSet(part))
            i += 1
        }
        return output.joined()
    }

    private static func splitKeepingCommas(_ text: String) -> [String] {
        var parts: [String] = [""]
        for c in text {
            if c == "," {
                parts.append(",")
                parts.append("")
            } else {
                parts[parts.count - 1].append(c)
            }
        }
        return parts
    }

    private static func tildes(_ text: String) -> Int { text.reduce(0) { $0 + ($1 == "~" ? 1 : 0) } }

    private static func shouldCombine(_ previous: String, _ next: String) -> Bool {
        tildes(previous) == 1 && tildes(next) == 1
    }

    private static func processSet(_ input: String) -> String {
        guard tildes(input) > 1 else { return input }
        var chars = Array(input)
        var leadingTilde = false
        if tildes(input) % 2 == 1, chars.first == "~" {
            chars.removeFirst()
            leadingTilde = true
        }
        while let first = chars.firstIndex(of: "~"), let last = chars.lastIndex(of: "~"), first != last {
            chars[first] = "<"
            chars[last] = ">"
        }
        return (leadingTilde ? "~" : "") + String(chars)
    }
}
