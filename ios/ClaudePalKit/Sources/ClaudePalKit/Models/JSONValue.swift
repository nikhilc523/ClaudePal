import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case string(String)
    case integer(Int)
    case double(Double)
    case boolean(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .boolean(value)
        } else if let value = try? container.decode(Int.self) {
            self = .integer(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case let .string(value):
            try container.encode(value)
        case let .integer(value):
            try container.encode(value)
        case let .double(value):
            try container.encode(value)
        case let .boolean(value):
            try container.encode(value)
        case let .object(value):
            try container.encode(value)
        case let .array(value):
            try container.encode(value)
        case .null:
            try container.encodeNil()
        }
    }

    public subscript(key: String) -> JSONValue? {
        guard case let .object(object) = self else {
            return nil
        }

        return object[key]
    }

    public var stringValue: String? {
        guard case let .string(value) = self else {
            return nil
        }

        return value
    }

    public var integerValue: Int? {
        guard case let .integer(value) = self else {
            return nil
        }

        return value
    }

    public var objectValue: [String: JSONValue]? {
        guard case let .object(value) = self else {
            return nil
        }

        return value
    }

    public var arrayValue: [JSONValue]? {
        guard case let .array(value) = self else {
            return nil
        }

        return value
    }

    public var prettyPrintedString: String? {
        guard JSONSerialization.isValidJSONObject(jsonObject) else {
            return stringValue
        }

        guard
            let data = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys]),
            let string = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return string
    }

    public var jsonObject: Any {
        switch self {
        case let .string(value):
            return value
        case let .integer(value):
            return value
        case let .double(value):
            return value
        case let .boolean(value):
            return value
        case let .object(value):
            return value.mapValues(\.jsonObject)
        case let .array(value):
            return value.map(\.jsonObject)
        case .null:
            return NSNull()
        }
    }
}
