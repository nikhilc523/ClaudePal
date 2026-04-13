import Foundation

public enum DecisionStatus: String, Codable, Sendable, CaseIterable {
    case pending, approved, denied, submitted, expired
}

public struct PendingDecision: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sessionId: String
    public var eventId: String
    public var status: DecisionStatus
    public var toolName: String?
    public var toolInput: String?
    public var isDestructive: Bool
    public var expiresAt: Date
    public var resolvedAt: Date?
    public var createdAt: Date

    public init(id: String = UUID().uuidString, sessionId: String, eventId: String,
                status: DecisionStatus = .pending, toolName: String? = nil, toolInput: String? = nil,
                isDestructive: Bool = false, expiresAt: Date = Date().addingTimeInterval(120),
                resolvedAt: Date? = nil, createdAt: Date = Date()) {
        self.id = id
        self.sessionId = sessionId
        self.eventId = eventId
        self.status = status
        self.toolName = toolName
        self.toolInput = toolInput
        self.isDestructive = isDestructive
        self.expiresAt = expiresAt
        self.resolvedAt = resolvedAt
        self.createdAt = createdAt
    }

    /// Whether Face ID is needed for this approval.
    public var requiresAuthentication: Bool { isDestructive }
}
