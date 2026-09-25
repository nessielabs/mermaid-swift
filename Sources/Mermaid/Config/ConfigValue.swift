import Foundation


/// A dynamically typed configuration value from front matter or an
/// `%%{init: ...}%%` directive.
public enum ConfigValue: Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([ConfigValue])
    case object([String: ConfigValue])
    case null

    public subscript(key: String) -> ConfigValue? {
        if case .object(let dict) = self { return dict[key] }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        case .bool(let b): return String(b)
        default: return nil
        }
    }

    public var numberValue: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingWhitespace().replacingOccurrences(of: "px", with: ""))
        default: return nil
        }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let b): return b
        case .string(let s): return ["true": true, "false": false][s.lowercased()]
        default: return nil
        }
    }

    public var objectValue: [String: ConfigValue]? {
        if case .object(let dict) = self { return dict }
        return nil
    }

    /// Deep-merges `other` into this value; objects merge key by key and
    /// every other value is replaced.
    public func merging(_ other: ConfigValue) -> ConfigValue {
        guard case .object(var base) = self, case .object(let overlay) = other else { return other }
        for (key, value) in overlay {
            base[key] = base[key].map { $0.merging(value) } ?? value
        }
        return .object(base)
    }
}
