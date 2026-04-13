import Foundation
import GRDB

public enum SessionStatus: String, Codable, Sendable, DatabaseValueConvertible {
    case active
    case waiting
    case idle
    case completed
    case failed
}

public struct Session: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var cwd: String
    public var displayName: String
    public var status: SessionStatus
    public var startedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        cwd: String,
        displayName: String,
        status: SessionStatus = .active,
        startedAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.cwd = cwd
        self.displayName = displayName
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
    }
}

extension Session: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "sessions"
}
