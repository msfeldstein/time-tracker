import Foundation

/// A JSON value used for request schemas and for tolerant decoding of model output.
public enum JSONValue: Sendable, Equatable, Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value):
            if value.rounded() == value, abs(value) < 1e15 {
                try container.encode(Int(value))
            } else {
                try container.encode(value)
            }
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    // MARK: Lenient accessors

    public subscript(key: String) -> JSONValue? {
        guard case .object(let object) = self else { return nil }
        if let exact = object[key] { return exact }
        // Accept camelCase / different casing for snake_case keys.
        let wanted = key.replacingOccurrences(of: "_", with: "").lowercased()
        return object.first { $0.key.replacingOccurrences(of: "_", with: "").lowercased() == wanted }?.value
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .number(let value): return value.rounded() == value ? String(Int(value)) : String(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    public var doubleValue: Double? {
        switch self {
        case .number(let value): return value
        case .string(let value): return Double(value.trimmingCharacters(in: .whitespaces))
        case .bool(let value): return value ? 1 : 0
        default: return nil
        }
    }

    public var intValue: Int? {
        doubleValue.map { Int($0.rounded()) }
    }

    public var boolValue: Bool? {
        switch self {
        case .bool(let value): return value
        case .string(let value): return ["true", "yes", "1"].contains(value.lowercased())
        case .number(let value): return value != 0
        default: return nil
        }
    }
}

extension JSONValue: ExpressibleByStringLiteral, ExpressibleByBooleanLiteral, ExpressibleByIntegerLiteral,
    ExpressibleByArrayLiteral, ExpressibleByDictionaryLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
    public init(booleanLiteral value: Bool) { self = .bool(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self = .object(Dictionary(elements, uniquingKeysWith: { $1 }))
    }
}

/// Small helpers for building strict JSON schemas (every object closes `additionalProperties`).
public enum JSONSchema {
    public static func object(_ properties: [String: JSONValue], required: [String]? = nil) -> JSONValue {
        [
            "type": "object",
            "properties": .object(properties),
            "required": .array((required ?? properties.keys.sorted()).map { .string($0) }),
            "additionalProperties": false,
        ]
    }

    public static func array(of items: JSONValue) -> JSONValue {
        ["type": "array", "items": items]
    }

    public static func string(_ description: String? = nil) -> JSONValue {
        description.map { ["type": "string", "description": .string($0)] } ?? ["type": "string"]
    }

    public static func integer(_ description: String? = nil) -> JSONValue {
        description.map { ["type": "integer", "description": .string($0)] } ?? ["type": "integer"]
    }

    public static func number(_ description: String? = nil) -> JSONValue {
        description.map { ["type": "number", "description": .string($0)] } ?? ["type": "number"]
    }

    public static func boolean() -> JSONValue {
        ["type": "boolean"]
    }

    public static func enumeration(_ values: [String]) -> JSONValue {
        ["type": "string", "enum": .array(values.map { .string($0) })]
    }
}
