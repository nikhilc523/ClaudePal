import Foundation

/// Raw hook payload from Claude Code.
/// Claude Code posts this JSON to the hook endpoint.
public struct HookPayload: Codable, Sendable {
    public let sessionId: String
    public let hookType: HookType
    public let event: HookEvent

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookType = "type"
        case event
    }

    public init(sessionId: String, hookType: HookType, event: HookEvent) {
        self.sessionId = sessionId
        self.hookType = hookType
        self.event = event
    }
}

public enum HookType: String, Codable, Sendable {
    case preToolUse = "PreToolUse"
    case postToolUse = "PostToolUse"
    case permissionRequest = "PermissionRequest"
    case notification = "Notification"
    case stop = "Stop"
}

/// The `event` field within a hook payload.
public struct HookEvent: Codable, Sendable {
    public let type: String?
    public let toolName: String?
    public let toolInput: JSONObject?
    public let title: String?
    public let message: String?
    public let sessionId: String?
    public let cwd: String?

    enum CodingKeys: String, CodingKey {
        case type
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case title
        case message
        case sessionId = "session_id"
        case cwd
    }

    public init(
        type: String? = nil,
        toolName: String? = nil,
        toolInput: JSONObject? = nil,
        title: String? = nil,
        message: String? = nil,
        sessionId: String? = nil,
        cwd: String? = nil
    ) {
        self.type = type
        self.toolName = toolName
        self.toolInput = toolInput
        self.title = title
        self.message = message
        self.sessionId = sessionId
        self.cwd = cwd
    }
}

/// Lightweight JSON object type for tool_input payloads.
public struct JSONObject: Codable, Sendable, Equatable {
    public let values: [String: JSONPrimitive]

    public init(_ values: [String: JSONPrimitive]) {
        self.values = values
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var result: [String: JSONPrimitive] = [:]
        for key in container.allKeys {
            if let str = try? container.decode(String.self, forKey: key) {
                result[key.stringValue] = .string(str)
            } else if let num = try? container.decode(Double.self, forKey: key) {
                result[key.stringValue] = .number(num)
            } else if let bool = try? container.decode(Bool.self, forKey: key) {
                result[key.stringValue] = .bool(bool)
            } else {
                // Store nested objects as their JSON string representation
                let nested = try container.decode(AnyCodable.self, forKey: key)
                if let data = try? JSONEncoder().encode(nested),
                   let str = String(data: data, encoding: .utf8) {
                    result[key.stringValue] = .string(str)
                }
            }
        }
        self.values = result
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in values {
            let codingKey = DynamicCodingKey(stringValue: key)
            switch value {
            case .string(let s): try container.encode(s, forKey: codingKey)
            case .number(let n): try container.encode(n, forKey: codingKey)
            case .bool(let b): try container.encode(b, forKey: codingKey)
            }
        }
    }

    /// Get the raw JSON string representation of the entire object.
    public func toJSONString() -> String? {
        guard let data = try? JSONEncoder().encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

public enum JSONPrimitive: Codable, Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
}

struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue: Int) {
        return nil
    }
}

/// Wrapper to decode arbitrary JSON for nested objects.
private struct AnyCodable: Codable {
    let value: Any

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let str = try? container.decode(String.self) { value = str }
        else if let num = try? container.decode(Double.self) { value = num }
        else if let bool = try? container.decode(Bool.self) { value = bool }
        else { value = "" }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let str = value as? String { try container.encode(str) }
        else if let num = value as? Double { try container.encode(num) }
        else if let bool = value as? Bool { try container.encode(bool) }
    }
}

// MARK: - Hook Responses

/// Response sent back to Claude Code for permission hooks.
public struct HookDecisionResponse: Codable, Sendable {
    public let decision: String
    public let reason: String?

    public init(decision: String, reason: String? = nil) {
        self.decision = decision
        self.reason = reason
    }

    public static let allow = HookDecisionResponse(decision: "allow")
    public static func deny(reason: String? = nil) -> HookDecisionResponse {
        HookDecisionResponse(decision: "deny", reason: reason)
    }
}
