import Foundation

/// A loosely-typed JSON value. Community APIs change field names over time, so the course
/// client reads through this and tries several known keys instead of failing outright.
public enum JSONValue: Codable, Hashable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        // Numbers are tried before booleans: some Foundation versions will happily decode
        // 0/1 as Bool, which would turn `"holes": 18`-style fields into garbage.
        if container.decodeNil() {
            self = .null
        } else if let n = try? container.decode(Double.self) {
            self = .number(n)
        } else if let s = try? container.decode(String.self) {
            self = .string(s)
        } else if let b = try? container.decode(Bool.self) {
            self = .bool(b)
        } else if let a = try? container.decode([JSONValue].self) {
            self = .array(a)
        } else if let o = try? container.decode([String: JSONValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let s): try container.encode(s)
        case .number(let n): try container.encode(n)
        case .bool(let b): try container.encode(b)
        case .object(let o): try container.encode(o)
        case .array(let a): try container.encode(a)
        case .null: try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        if case .object(let o) = self { return o[key] }
        return nil
    }

    /// First non-null value among several candidate keys.
    public func first(_ keys: String...) -> JSONValue? {
        first(keys)
    }

    public func first(_ keys: [String]) -> JSONValue? {
        for key in keys {
            if let value = self[key], value != .null { return value }
        }
        return nil
    }

    public var string: String? {
        switch self {
        case .string(let s): return s.isEmpty ? nil : s
        case .number(let n): return n == n.rounded() ? String(Int(n)) : String(n)
        default: return nil
        }
    }

    public var double: Double? {
        switch self {
        case .number(let n): return n
        case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
        default: return nil
        }
    }

    public var int: Int? {
        double.map { Int($0.rounded()) }
    }

    public var array: [JSONValue]? {
        if case .array(let a) = self { return a }
        return nil
    }

    public var object: [String: JSONValue]? {
        if case .object(let o) = self { return o }
        return nil
    }
}
