import Foundation

extension LabelParser {
    /// Decodes Mermaid's entity codes: `#quot;`, `#35;`, and `#x23;`.
    /// Mermaid uses a leading `#` instead of `&` so that entities survive
    /// inside its own quoting rules.
    static func decodeMermaidEntities(_ text: String) -> String {
        replacingEntities(in: text, prefix: "#")
    }

    /// Decodes HTML entities such as `&amp;`, `&#35;`, and `&#x23;`.
    static func decodeHTMLEntities(_ text: String) -> String {
        replacingEntities(in: text, prefix: "&")
    }

    private static func replacingEntities(in text: String, prefix: Character) -> String {
        guard text.contains(prefix) else { return text }
        var result = ""
        var index = text.startIndex
        while index < text.endIndex {
            let c = text[index]
            guard c == prefix,
                  let semicolon = text[index...].prefix(12).firstIndex(of: ";"),
                  let decoded = decodeEntity(String(text[text.index(after: index)..<semicolon])) else {
                result.append(c)
                index = text.index(after: index)
                continue
            }
            result += decoded
            index = text.index(after: semicolon)
        }
        return result
    }

    private static func decodeEntity(_ name: String) -> String? {
        if name.hasPrefix("x") || name.hasPrefix("X"), let code = UInt32(name.dropFirst(), radix: 16) {
            return Unicode.Scalar(code).map { String(Character($0)) }
        }
        if let code = UInt32(name.drop { $0 == "#" }), name.first?.isNumber ?? false || name.hasPrefix("#") {
            return Unicode.Scalar(code).map { String(Character($0)) }
        }
        return namedEntities[name.lowercased()]
    }

    private static let namedEntities: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "copy": "©", "reg": "®", "trade": "™", "hellip": "…", "mdash": "—", "ndash": "–",
        "larr": "←", "rarr": "→", "uarr": "↑", "darr": "↓", "harr": "↔", "lsquo": "‘", "rsquo": "’",
        "ldquo": "“", "rdquo": "”", "bull": "•", "middot": "·", "deg": "°", "times": "×", "divide": "÷",
        "plusmn": "±", "ne": "≠", "le": "≤", "ge": "≥", "infin": "∞", "check": "✓", "hearts": "♥",
        "semi": ";", "colon": ":", "num": "#", "lpar": "(", "rpar": ")", "lsqb": "[", "rsqb": "]",
        "lcub": "{", "rcub": "}", "vert": "|", "excl": "!", "quest": "?",
    ]

    /// Removes Font Awesome tokens such as `fa:fa-car` and `fab:fa-github`.
    static func removeIcons(_ text: String) -> String {
        guard text.contains(":fa-") else { return text }
        let pattern = #"\b(?:fa|fab|fas|far|fal|fak):fa-[a-z0-9-]+\s?"#
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }
}
