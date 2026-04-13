import Foundation
#if canImport(Observation)
import Observation
#endif

/// Mock data provider for development and SwiftUI previews.
@available(iOS 17.0, watchOS 10.0, macOS 14.0, *)
@MainActor @Observable
public final class MockDataProvider: DataProvider {
    public var sessions: [Session]
    public var pendingDecisions: [PendingDecision]
    public var recentEvents: [Event]
    public var connectionState: ConnectionState

    public init() {
        self.connectionState = .connected
        self.sessions = Self.makeSessions()
        self.pendingDecisions = []
        self.recentEvents = []

        let (decisions, events) = Self.makeDecisionsAndEvents(sessions: self.sessions)
        self.pendingDecisions = decisions
        self.recentEvents = events
    }

    // MARK: - DataProvider

    public func start() async {
        connectionState = .syncing
        try? await Task.sleep(nanoseconds: 500_000_000)
        connectionState = .connected
    }

    public func refresh() async {
        connectionState = .syncing
        try? await Task.sleep(nanoseconds: 300_000_000)
        connectionState = .connected
    }

    public func approve(decisionId: String) async throws {
        guard let idx = pendingDecisions.firstIndex(where: { $0.id == decisionId }) else { return }
        pendingDecisions[idx].status = .approved
        pendingDecisions[idx].resolvedAt = Date()
    }

    public func deny(decisionId: String, reason: String?) async throws {
        guard let idx = pendingDecisions.firstIndex(where: { $0.id == decisionId }) else { return }
        pendingDecisions[idx].status = .denied
        pendingDecisions[idx].resolvedAt = Date()
    }

    public func events(for sessionId: String) -> [Event] {
        recentEvents.filter { $0.sessionId == sessionId }
    }

    // MARK: - Static Preview

    public static var preview: MockDataProvider { MockDataProvider() }

    // MARK: - Mock Data Generation

    private static func makeSessions() -> [Session] {
        let now = Date()
        return [
            Session(id: "session-1", cwd: "/Users/dev/MyProject",
                    displayName: "MyProject", status: .active,
                    startedAt: now.addingTimeInterval(-3600), updatedAt: now.addingTimeInterval(-30)),
            Session(id: "session-2", cwd: "/Users/dev/Backend",
                    displayName: "Backend", status: .waiting,
                    startedAt: now.addingTimeInterval(-7200), updatedAt: now.addingTimeInterval(-60)),
            Session(id: "session-3", cwd: "/Users/dev/Docs",
                    displayName: "Docs", status: .completed,
                    startedAt: now.addingTimeInterval(-86400), updatedAt: now.addingTimeInterval(-3600)),
        ]
    }

    private static func makeDecisionsAndEvents(sessions: [Session]) -> ([PendingDecision], [Event]) {
        let now = Date()
        var events: [Event] = []
        var decisions: [PendingDecision] = []

        // Session 1: active, has a pending Bash approval
        let ev1 = Event(id: "ev-1", sessionId: "session-1", type: .permissionRequested,
                        title: "Bash", message: "ls -la /tmp",
                        payload: #"{"command":"ls -la /tmp"}"#,
                        createdAt: now.addingTimeInterval(-30))
        events.append(ev1)
        decisions.append(PendingDecision(
            id: "dec-1", sessionId: "session-1", eventId: "ev-1",
            toolName: "Bash", toolInput: "ls -la /tmp",
            isDestructive: false, expiresAt: now.addingTimeInterval(90)
        ))

        // Session 2: waiting, has a destructive rm -rf pending
        let ev2 = Event(id: "ev-2", sessionId: "session-2", type: .permissionRequested,
                        title: "Bash", message: "rm -rf /tmp/build-cache",
                        payload: #"{"command":"rm -rf /tmp/build-cache"}"#,
                        createdAt: now.addingTimeInterval(-15))
        events.append(ev2)
        decisions.append(PendingDecision(
            id: "dec-2", sessionId: "session-2", eventId: "ev-2",
            toolName: "Bash", toolInput: "rm -rf /tmp/build-cache",
            isDestructive: true, expiresAt: now.addingTimeInterval(105)
        ))

        // More events for history
        events.append(contentsOf: [
            Event(id: "ev-3", sessionId: "session-1", type: .sessionStarted,
                  title: "Session started", createdAt: now.addingTimeInterval(-3600)),
            Event(id: "ev-4", sessionId: "session-1", type: .sessionUpdated,
                  title: "Tool completed: Read", createdAt: now.addingTimeInterval(-3500)),
            Event(id: "ev-5", sessionId: "session-1", type: .sessionUpdated,
                  title: "Tool completed: Grep", createdAt: now.addingTimeInterval(-3400)),
            Event(id: "ev-6", sessionId: "session-1", type: .notificationReceived,
                  title: "Notification", message: "Build started", createdAt: now.addingTimeInterval(-3300)),
            Event(id: "ev-7", sessionId: "session-2", type: .sessionStarted,
                  title: "Session started", createdAt: now.addingTimeInterval(-7200)),
            Event(id: "ev-8", sessionId: "session-2", type: .permissionRequested,
                  title: "Write", message: "Created config.json", createdAt: now.addingTimeInterval(-7000)),
            Event(id: "ev-9", sessionId: "session-3", type: .sessionStarted,
                  title: "Session started", createdAt: now.addingTimeInterval(-86400)),
            Event(id: "ev-10", sessionId: "session-3", type: .taskCompleted,
                  title: "Task completed", message: "Documentation updated", createdAt: now.addingTimeInterval(-3600)),
        ])

        return (decisions, events.sorted { $0.createdAt > $1.createdAt })
    }
}
