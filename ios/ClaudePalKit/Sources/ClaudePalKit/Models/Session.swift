import Foundation

public enum SessionStatus: String, Codable, Sendable, CaseIterable {
    case active, waiting, idle, completed, failed
}

public struct Session: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var cwd: String
    public var displayName: String
    public var status: SessionStatus
    public var startedAt: Date
    public var updatedAt: Date

    public init(id: String = UUID().uuidString, cwd: String, displayName: String,
                status: SessionStatus = .active, startedAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.cwd = cwd
        self.displayName = displayName
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}
