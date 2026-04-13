import Foundation
import GRDB

public enum EventType: String, Codable, Sendable, DatabaseValueConvertible {
    case permissionRequested = "permission_requested"
    case inputRequested = "input_requested"
    case taskCompleted = "task_completed"
    case taskCreated = "task_created"
    case sessionStarted = "session_started"
    case sessionUpdated = "session_updated"
    case sessionEnded = "session_ended"
    case notificationReceived = "notification_received"
    case errorReceived = "error_received"
}

public struct Event: Identifiable, Codable, Equatable, Sendable {
    public var id: String
    public var sessionId: String
    public var type: EventType
    public var title: String
    public var message: String
    public var payload: String?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        sessionId: String,
        type: EventType,
        title: String,
        message: String,
        payload: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.sessionId = sessionId
        self.type = type
        self.title = title
        self.message = message
        self.payload = payload
        self.createdAt = createdAt
    }
}

extension Event: FetchableRecord, PersistableRecord {
    public static let databaseTableName = "events"
}
