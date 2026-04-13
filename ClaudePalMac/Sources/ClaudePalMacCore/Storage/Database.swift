import Foundation
import GRDB

public final class AppDatabase: Sendable {
    private let dbWriter: any DatabaseWriter

    /// Production initializer — uses DatabasePool with WAL mode.
    public init(path: String) throws {
        var config = Configuration()
        config.foreignKeysEnabled = true
        dbWriter = try DatabasePool(path: path, configuration: config)
        try migrate()
    }

    /// In-memory database for testing — uses DatabaseQueue (no WAL needed).
    public static func inMemory() throws -> AppDatabase {
        var config = Configuration()
        config.foreignKeysEnabled = true
        let queue = try DatabaseQueue(configuration: config)
        let db = AppDatabase(writer: queue)
        try db.migrate()
        return db
    }

    private init(writer: any DatabaseWriter) {
        self.dbWriter = writer
    }

    private func migrate() throws {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_create_tables") { db in
            try db.create(table: "sessions") { t in
                t.primaryKey("id", .text).notNull()
                t.column("cwd", .text).notNull()
                t.column("displayName", .text).notNull()
                t.column("status", .text).notNull()
                t.column("startedAt", .datetime).notNull()
                t.column("updatedAt", .datetime).notNull()
            }

            try db.create(table: "events") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("title", .text).notNull()
                t.column("message", .text).notNull()
                t.column("payload", .text)
                t.column("createdAt", .datetime).notNull()
            }

            try db.create(table: "pending_decisions") { t in
                t.primaryKey("id", .text).notNull()
                t.column("sessionId", .text).notNull()
                    .references("sessions", onDelete: .cascade)
                t.column("eventId", .text).notNull()
                    .references("events", onDelete: .cascade)
                t.column("status", .text).notNull()
                t.column("toolName", .text)
                t.column("toolInput", .text)
                t.column("isDestructive", .boolean).notNull().defaults(to: false)
                t.column("expiresAt", .datetime).notNull()
                t.column("resolvedAt", .datetime)
                t.column("createdAt", .datetime).notNull()
            }
        }

        try migrator.migrate(dbWriter)
    }

    // MARK: - Sessions

    public func saveSession(_ session: Session) throws {
        try dbWriter.write { db in
            try session.save(db)
        }
    }

    public func fetchSession(id: String) throws -> Session? {
        try dbWriter.read { db in
            try Session.fetchOne(db, key: id)
        }
    }

    public func fetchAllSessions() throws -> [Session] {
        try dbWriter.read { db in
            try Session.order(Column("updatedAt").desc).fetchAll(db)
        }
    }

    public func updateSessionStatus(id: String, status: SessionStatus) throws {
        try dbWriter.write { db in
            if var session = try Session.fetchOne(db, key: id) {
                session.status = status
                session.updatedAt = Date()
                try session.update(db)
            }
        }
    }

    public func deleteSession(id: String) throws {
        try dbWriter.write { db in
            _ = try Session.deleteOne(db, key: id)
        }
    }

    // MARK: - Events

    public func saveEvent(_ event: Event) throws {
        try dbWriter.write { db in
            try event.save(db)
        }
    }

    public func fetchEvent(id: String) throws -> Event? {
        try dbWriter.read { db in
            try Event.fetchOne(db, key: id)
        }
    }

    public func fetchEvents(sessionId: String) throws -> [Event] {
        try dbWriter.read { db in
            try Event
                .filter(Column("sessionId") == sessionId)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func fetchRecentEvents(limit: Int = 50) throws -> [Event] {
        try dbWriter.read { db in
            try Event
                .order(Column("createdAt").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    // MARK: - Pending Decisions

    public func savePendingDecision(_ decision: PendingDecision) throws {
        try dbWriter.write { db in
            try decision.save(db)
        }
    }

    public func fetchPendingDecision(id: String) throws -> PendingDecision? {
        try dbWriter.read { db in
            try PendingDecision.fetchOne(db, key: id)
        }
    }

    public func fetchPendingDecisions() throws -> [PendingDecision] {
        try dbWriter.read { db in
            try PendingDecision
                .filter(Column("status") == DecisionStatus.pending.rawValue)
                .order(Column("createdAt").desc)
                .fetchAll(db)
        }
    }

    public func resolveDecision(id: String, status: DecisionStatus) throws {
        try dbWriter.write { db in
            if var decision = try PendingDecision.fetchOne(db, key: id) {
                decision.status = status
                decision.resolvedAt = Date()
                try decision.update(db)
            }
        }
    }

    /// Auto-resolve pending decisions for a session+tool when PostToolUse arrives.
    /// In async hook mode the user approves in the terminal, so these are already handled.
    public func autoResolvePendingDecisions(sessionId: String, toolName: String) throws {
        try dbWriter.write { db in
            try db.execute(
                sql: """
                    UPDATE pending_decisions
                    SET status = ?, resolvedAt = ?
                    WHERE sessionId = ? AND toolName = ? AND status = ?
                    """,
                arguments: [
                    DecisionStatus.approved.rawValue,
                    Date(),
                    sessionId,
                    toolName,
                    DecisionStatus.pending.rawValue,
                ]
            )
        }
    }

    public func expireStaleDecisions() throws -> Int {
        try dbWriter.write { db in
            let now = Date()
            let count = try PendingDecision
                .filter(Column("status") == DecisionStatus.pending.rawValue)
                .filter(Column("expiresAt") < now)
                .fetchCount(db)

            try db.execute(
                sql: """
                    UPDATE pending_decisions
                    SET status = ?, resolvedAt = ?
                    WHERE status = ? AND expiresAt < ?
                    """,
                arguments: [
                    DecisionStatus.expired.rawValue,
                    now,
                    DecisionStatus.pending.rawValue,
                    now,
                ]
            )

            return count
        }
    }
}
