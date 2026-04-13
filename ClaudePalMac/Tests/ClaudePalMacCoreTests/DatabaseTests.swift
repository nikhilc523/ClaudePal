import Testing
import Foundation
@testable import ClaudePalMacCore

@Suite("AppDatabase Tests")
struct DatabaseTests {

    // MARK: - Session Tests

    @Test("Create and fetch a session")
    func createAndFetchSession() throws {
        let db = try AppDatabase.inMemory()
        let session = Session(
            id: "sess-1",
            cwd: "/Users/test/project",
            displayName: "project"
        )

        try db.saveSession(session)
        let fetched = try db.fetchSession(id: "sess-1")

        #expect(fetched != nil)
        #expect(fetched?.id == "sess-1")
        #expect(fetched?.cwd == "/Users/test/project")
        #expect(fetched?.displayName == "project")
        #expect(fetched?.status == .active)
    }

    @Test("Fetch all sessions ordered by updatedAt descending")
    func fetchAllSessionsOrdered() throws {
        let db = try AppDatabase.inMemory()

        let older = Session(
            id: "sess-old",
            cwd: "/old",
            displayName: "old",
            updatedAt: Date(timeIntervalSince1970: 1000)
        )
        let newer = Session(
            id: "sess-new",
            cwd: "/new",
            displayName: "new",
            updatedAt: Date(timeIntervalSince1970: 2000)
        )

        try db.saveSession(older)
        try db.saveSession(newer)

        let all = try db.fetchAllSessions()
        #expect(all.count == 2)
        #expect(all[0].id == "sess-new")
        #expect(all[1].id == "sess-old")
    }

    @Test("Update session status")
    func updateSessionStatus() throws {
        let db = try AppDatabase.inMemory()
        let session = Session(id: "sess-1", cwd: "/test", displayName: "test")
        try db.saveSession(session)

        try db.updateSessionStatus(id: "sess-1", status: .waiting)

        let fetched = try db.fetchSession(id: "sess-1")
        #expect(fetched?.status == .waiting)
    }

    @Test("Fetch nonexistent session returns nil")
    func fetchNonexistentSession() throws {
        let db = try AppDatabase.inMemory()
        let result = try db.fetchSession(id: "doesnt-exist")
        #expect(result == nil)
    }

    // MARK: - Event Tests

    @Test("Create and fetch an event")
    func createAndFetchEvent() throws {
        let db = try AppDatabase.inMemory()
        let session = Session(id: "sess-1", cwd: "/test", displayName: "test")
        try db.saveSession(session)

        let event = Event(
            id: "evt-1",
            sessionId: "sess-1",
            type: .permissionRequested,
            title: "Bash: rm -rf /tmp/test",
            message: "Claude wants to run a bash command"
        )
        try db.saveEvent(event)

        let fetched = try db.fetchEvent(id: "evt-1")
        #expect(fetched != nil)
        #expect(fetched?.type == .permissionRequested)
        #expect(fetched?.sessionId == "sess-1")
        #expect(fetched?.title == "Bash: rm -rf /tmp/test")
    }

    @Test("Fetch events by session ID")
    func fetchEventsBySession() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/a", displayName: "a"))
        try db.saveSession(Session(id: "s2", cwd: "/b", displayName: "b"))

        try db.saveEvent(Event(id: "e1", sessionId: "s1", type: .taskCompleted, title: "Done", message: "ok"))
        try db.saveEvent(Event(id: "e2", sessionId: "s1", type: .notificationReceived, title: "Info", message: "hi"))
        try db.saveEvent(Event(id: "e3", sessionId: "s2", type: .taskCreated, title: "New", message: "started"))

        let s1Events = try db.fetchEvents(sessionId: "s1")
        #expect(s1Events.count == 2)

        let s2Events = try db.fetchEvents(sessionId: "s2")
        #expect(s2Events.count == 1)
    }

    @Test("Fetch recent events with limit")
    func fetchRecentEventsWithLimit() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/a", displayName: "a"))

        for i in 0..<10 {
            try db.saveEvent(Event(
                id: "e\(i)",
                sessionId: "s1",
                type: .notificationReceived,
                title: "Event \(i)",
                message: "msg",
                createdAt: Date(timeIntervalSince1970: Double(i) * 100)
            ))
        }

        let recent = try db.fetchRecentEvents(limit: 3)
        #expect(recent.count == 3)
        // Most recent first
        #expect(recent[0].id == "e9")
    }

    @Test("Event payload round-trips")
    func eventPayloadRoundTrip() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/a", displayName: "a"))

        let payload = #"{"tool":"Bash","command":"ls"}"#
        try db.saveEvent(Event(
            id: "e1",
            sessionId: "s1",
            type: .permissionRequested,
            title: "Bash",
            message: "run ls",
            payload: payload
        ))

        let fetched = try db.fetchEvent(id: "e1")
        #expect(fetched?.payload == payload)
    }

    // MARK: - Pending Decision Tests

    @Test("Create and fetch a pending decision")
    func createAndFetchPendingDecision() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/test", displayName: "test"))
        try db.saveEvent(Event(id: "e1", sessionId: "s1", type: .permissionRequested, title: "Bash", message: "cmd"))

        let decision = PendingDecision(
            id: "d1",
            sessionId: "s1",
            eventId: "e1",
            toolName: "Bash",
            toolInput: "rm -rf /tmp/test",
            isDestructive: true,
            expiresAt: Date().addingTimeInterval(300)
        )
        try db.savePendingDecision(decision)

        let fetched = try db.fetchPendingDecision(id: "d1")
        #expect(fetched != nil)
        #expect(fetched?.status == .pending)
        #expect(fetched?.toolName == "Bash")
        #expect(fetched?.isDestructive == true)
    }

    @Test("Fetch only pending decisions")
    func fetchOnlyPendingDecisions() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/test", displayName: "test"))
        try db.saveEvent(Event(id: "e1", sessionId: "s1", type: .permissionRequested, title: "A", message: "a"))
        try db.saveEvent(Event(id: "e2", sessionId: "s1", type: .permissionRequested, title: "B", message: "b"))

        let d1 = PendingDecision(id: "d1", sessionId: "s1", eventId: "e1", expiresAt: Date().addingTimeInterval(300))
        var d2 = PendingDecision(id: "d2", sessionId: "s1", eventId: "e2", expiresAt: Date().addingTimeInterval(300))
        d2.status = .approved
        d2.resolvedAt = Date()

        try db.savePendingDecision(d1)
        try db.savePendingDecision(d2)

        let pending = try db.fetchPendingDecisions()
        #expect(pending.count == 1)
        #expect(pending[0].id == "d1")
    }

    @Test("Resolve a decision")
    func resolveDecision() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/test", displayName: "test"))
        try db.saveEvent(Event(id: "e1", sessionId: "s1", type: .permissionRequested, title: "A", message: "a"))

        let decision = PendingDecision(id: "d1", sessionId: "s1", eventId: "e1", expiresAt: Date().addingTimeInterval(300))
        try db.savePendingDecision(decision)

        try db.resolveDecision(id: "d1", status: .approved)

        let fetched = try db.fetchPendingDecision(id: "d1")
        #expect(fetched?.status == .approved)
        #expect(fetched?.resolvedAt != nil)
    }

    @Test("Expire stale decisions")
    func expireStaleDecisions() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/test", displayName: "test"))
        try db.saveEvent(Event(id: "e1", sessionId: "s1", type: .permissionRequested, title: "A", message: "a"))
        try db.saveEvent(Event(id: "e2", sessionId: "s1", type: .permissionRequested, title: "B", message: "b"))

        // Already expired
        let stale = PendingDecision(
            id: "d1", sessionId: "s1", eventId: "e1",
            expiresAt: Date().addingTimeInterval(-60)
        )
        // Still valid
        let fresh = PendingDecision(
            id: "d2", sessionId: "s1", eventId: "e2",
            expiresAt: Date().addingTimeInterval(300)
        )

        try db.savePendingDecision(stale)
        try db.savePendingDecision(fresh)

        let expiredCount = try db.expireStaleDecisions()
        #expect(expiredCount == 1)

        let d1 = try db.fetchPendingDecision(id: "d1")
        #expect(d1?.status == .expired)

        let d2 = try db.fetchPendingDecision(id: "d2")
        #expect(d2?.status == .pending)
    }

    @Test("Cascade deletes events and decisions when session is deleted")
    func cascadeDelete() throws {
        let db = try AppDatabase.inMemory()
        try db.saveSession(Session(id: "s1", cwd: "/test", displayName: "test"))
        try db.saveEvent(Event(id: "e1", sessionId: "s1", type: .permissionRequested, title: "A", message: "a"))
        try db.savePendingDecision(PendingDecision(id: "d1", sessionId: "s1", eventId: "e1", expiresAt: Date().addingTimeInterval(300)))

        // Verify everything exists
        #expect(try db.fetchEvent(id: "e1") != nil)
        #expect(try db.fetchPendingDecision(id: "d1") != nil)

        // Delete the session — events and decisions should cascade
        try db.deleteSession(id: "s1")

        #expect(try db.fetchSession(id: "s1") == nil)
        #expect(try db.fetchEvent(id: "e1") == nil)
        #expect(try db.fetchPendingDecision(id: "d1") == nil)
    }
}
