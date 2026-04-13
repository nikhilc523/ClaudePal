import Foundation

/// Raw payload as Claude Code sends it to hooks via stdin.
/// This is the actual wire format — we convert it to our internal HookPayload for processing.
public struct RawHookPayload: Codable, Sendable {
    public let sessionId: String
    public let hookEventName: String
    public let cwd: String?
    public let transcriptPath: String?
    public let permissionMode: String?

    // PreToolUse / PostToolUse fields
    public let toolName: String?
    public let toolInput: JSONObject?
    public let toolUseId: String?

    // PostToolUse only
    public let toolResponse: JSONObject?

    // Notification fields
    public let message: String?
    public let title: String?
    public let notificationType: String?

    // Stop fields
    public let stopReason: String?

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case hookEventName = "hook_event_name"
        case cwd
        case transcriptPath = "transcript_path"
        case permissionMode = "permission_mode"
        case toolName = "tool_name"
        case toolInput = "tool_input"
        case toolUseId = "tool_use_id"
        case toolResponse = "tool_response"
        case message, title
        case notificationType = "notification_type"
        case stopReason = "stop_reason"
    }

    /// Convert to our internal HookPayload format.
    public func toHookPayload() -> HookPayload {
        let hookType: HookType
        switch hookEventName {
        case "PreToolUse": hookType = .preToolUse
        case "PostToolUse": hookType = .postToolUse
        case "PermissionRequest": hookType = .permissionRequest
        case "Notification": hookType = .notification
        case "Stop": hookType = .stop
        default: hookType = .notification // fallback: treat unknown as notification
        }

        let event = HookEvent(
            type: hookEventName,
            toolName: toolName,
            toolInput: toolInput,
            title: title,
            message: message ?? stopReason,
            sessionId: sessionId,
            cwd: cwd
        )

        return HookPayload(
            sessionId: sessionId,
            hookType: hookType,
            event: event
        )
    }
}

/// Response format that Claude Code expects from hooks.
/// Claude Code reads stdout JSON and uses these fields.
public struct RawHookResponse: Codable, Sendable {
    /// For PreToolUse: "approve" to allow, "block" to deny
    public let decision: String?
    /// Reason shown when blocking
    public let reason: String?

    public init(decision: String? = nil, reason: String? = nil) {
        self.decision = decision
        self.reason = reason
    }

    /// Convert from our internal response to Claude Code wire format.
    public static func from(_ response: HookDecisionResponse?) -> RawHookResponse {
        guard let response else { return RawHookResponse() }
        switch response.decision {
        case "allow":
            return RawHookResponse(decision: "approve")
        case "deny":
            return RawHookResponse(decision: "block", reason: response.reason)
        default:
            return RawHookResponse(decision: response.decision, reason: response.reason)
        }
    }
}
