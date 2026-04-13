import Foundation

/// Represents an approval command sent from iPhone/Watch to macOS via CloudKit.
public struct ApprovalCommand: Codable, Sendable {
    public let commandId: String
    public let pendingDecisionId: String
    public let action: String          // "approve" or "deny"
    public let reason: String?
    public let sourceDevice: String    // "iphone" or "watch"
    public let createdAt: Date

    public init(pendingDecisionId: String, action: String, reason: String? = nil,
                sourceDevice: String = "iphone") {
        self.commandId = UUID().uuidString
        self.pendingDecisionId = pendingDecisionId
        self.action = action
        self.reason = reason
        self.sourceDevice = sourceDevice
        self.createdAt = Date()
    }
}
