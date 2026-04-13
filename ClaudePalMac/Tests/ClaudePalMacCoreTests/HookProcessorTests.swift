import Testing
import Foundation
@testable import ClaudePalMacCore

@Suite("HookProcessor Tests")
struct HookProcessorTests {

    private func makeProcessor(timeout: TimeInterval = 5) throws -> (HookProcessor, AppDatabase) {
        let db = try AppDatabase.inMemory()
        let processor = HookProcessor(db: db, defaultTimeoutSeconds: timeout)
        return (processor, db)
    }

    // MARK: - Notification Processing

    @Test("Notification hook creates session and event, returns nil")
    func notificationCreatesSessionAndEvent() async throws {
        let (processor, db) = try makeProcessor()

        let payload = HookPayload(
            sessionId: "sess-1",
            hookType: .notification,
            event: HookEvent(
                title: "Task started",
                message: "Working on feature X",
                cwd: "/Users/test/myproject"
            )
        )

        let response = try await processor.process(payload)
        #expect(response == nil)

        // Session should be auto-created
        let session = try db.fetchSession(id: "sess-1")
        #expect(session != nil)
        #expect(session?.cwd == "/Users/test/myproject")
        #expect(session?.displayName == "myproject")

        // Event should be stored
        let events = try db.fetchEvents(sessionId: "sess-1")
        #expect(events.count == 1)
        #expect(events[0].type == .notificationReceived)
        #expect(events[0].title == "Task started")
    }

    // MARK: - Stop Processing

    @Test("Stop hook marks session completed")
    func stopMarksSessionCompleted() async throws {
        let (processor, db) = try makeProcessor()

        // First create session via notification
        let notif = HookPayload(
            sessionId: "sess-1",
            hookType: .notification,
            event: HookEvent(title: "hi", message: "hi", cwd: "/test")
        )
        _ = try await processor.process(notif)

        // Now stop
        let stop = HookPayload(
            sessionId: "sess-1",
            hookType: .stop,
            event: HookEvent(message: "User stopped")
        )
        let response = try await processor.process(stop)
        #expect(response == nil)

        let session = try db.fetchSession(id: "sess-1")
        #expect(session?.status == .completed)

        let events = try db.fetchEvents(sessionId: "sess-1")
        let stopEvent = events.first { $0.type == .taskCompleted }
        #expect(stopEvent != nil)
    }

    // MARK: - PostToolUse Processing

    @Test("PostToolUse records event and keeps session active")
    func postToolUseRecordsEvent() async throws {
        let (processor, db) = try makeProcessor()

        let payload = HookPayload(
            sessionId: "sess-1",
            hookType: .postToolUse,
            event: HookEvent(toolName: "Bash", cwd: "/test")
        )

        let response = try await processor.process(payload)
        #expect(response == nil)

        let session = try db.fetchSession(id: "sess-1")
        #expect(session?.status == .active)
    }

    // MARK: - Permission Request Processing

    @Test("PreToolUse creates pending decision and event")
    func preToolUseCreatesPendingDecision() async throws {
        let (processor, db) = try makeProcessor(timeout: 2)

        // Run the permission request in a task so we can resolve it
        let processTask = Task {
            let payload = HookPayload(
                sessionId: "sess-1",
                hookType: .preToolUse,
                event: HookEvent(
                    toolName: "Bash",
                    toolInput: JSONObject(["command": .string("ls -la")]),
                    cwd: "/test"
                )
            )
            return try await processor.process(payload)
        }

        // Give time for the decision to be created
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s

        // Verify pending decision was created
        let decisions = try db.fetchPendingDecisions()
        #expect(decisions.count == 1)
        #expect(decisions[0].toolName == "Bash")
        #expect(decisions[0].status == .pending)

        // Session should be in waiting state
        let session = try db.fetchSession(id: "sess-1")
        #expect(session?.status == .waiting)

        // Event should exist
        let events = try db.fetchEvents(sessionId: "sess-1")
        #expect(events.count == 1)
        #expect(events[0].type == .permissionRequested)

        // Resolve it
        try await processor.resolve(decisionId: decisions[0].id, approved: true)

        let response = try await processTask.value
        #expect(response?.decision == "allow")
    }

    @Test("Denied permission returns deny response")
    func deniedPermissionReturnsDeny() async throws {
        let (processor, db) = try makeProcessor(timeout: 2)

        let processTask = Task {
            let payload = HookPayload(
                sessionId: "sess-1",
                hookType: .preToolUse,
                event: HookEvent(
                    toolName: "Bash",
                    toolInput: JSONObject(["command": .string("rm -rf /")]),
                    cwd: "/test"
                )
            )
            return try await processor.process(payload)
        }

        try await Task.sleep(nanoseconds: 100_000_000)

        let decisions = try db.fetchPendingDecisions()
        #expect(decisions.count == 1)
        #expect(decisions[0].isDestructive == true)

        try await processor.resolve(decisionId: decisions[0].id, approved: false, reason: "Too dangerous")

        let response = try await processTask.value
        #expect(response?.decision == "deny")
        #expect(response?.reason == "Too dangerous")
    }

    @Test("Permission request times out gracefully")
    func permissionTimesOut() async throws {
        let (processor, _) = try makeProcessor(timeout: 1)

        let payload = HookPayload(
            sessionId: "sess-1",
            hookType: .preToolUse,
            event: HookEvent(toolName: "Write", cwd: "/test")
        )

        // This should throw after 1 second timeout
        do {
            _ = try await processor.process(payload)
            Issue.record("Expected timeout error")
        } catch is HookTimeoutError {
            // Expected
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    // MARK: - Session Auto-Creation

    @Test("Session is created automatically from any hook type")
    func sessionAutoCreated() async throws {
        let (processor, db) = try makeProcessor()

        let payload = HookPayload(
            sessionId: "new-session",
            hookType: .notification,
            event: HookEvent(
                title: "Test",
                message: "Test",
                cwd: "/Users/dev/my-app"
            )
        )
        _ = try await processor.process(payload)

        let session = try db.fetchSession(id: "new-session")
        #expect(session != nil)
        #expect(session?.displayName == "my-app")
    }

    @Test("Existing session is not overwritten")
    func existingSessionNotOverwritten() async throws {
        let (processor, db) = try makeProcessor()

        // First hook creates session
        let p1 = HookPayload(
            sessionId: "sess-1",
            hookType: .notification,
            event: HookEvent(title: "A", message: "a", cwd: "/original")
        )
        _ = try await processor.process(p1)

        // Second hook with different cwd should not overwrite
        let p2 = HookPayload(
            sessionId: "sess-1",
            hookType: .notification,
            event: HookEvent(title: "B", message: "b", cwd: "/different")
        )
        _ = try await processor.process(p2)

        let session = try db.fetchSession(id: "sess-1")
        #expect(session?.cwd == "/original")
    }

    // MARK: - Destructive Detection

    @Test("Destructive tool detection")
    func destructiveToolDetection() {
        // rm commands
        #expect(HookProcessor.isDestructiveTool(
            name: "Bash",
            input: JSONObject(["command": .string("rm -rf /tmp/stuff")])
        ) == true)

        // git reset --hard
        #expect(HookProcessor.isDestructiveTool(
            name: "Bash",
            input: JSONObject(["command": .string("git reset --hard HEAD~3")])
        ) == true)

        // git push --force
        #expect(HookProcessor.isDestructiveTool(
            name: "Bash",
            input: JSONObject(["command": .string("git push --force origin main")])
        ) == true)

        // Safe commands
        #expect(HookProcessor.isDestructiveTool(
            name: "Bash",
            input: JSONObject(["command": .string("ls -la")])
        ) == false)

        // Non-Bash tools are not flagged
        #expect(HookProcessor.isDestructiveTool(
            name: "Read",
            input: JSONObject(["file_path": .string("/etc/passwd")])
        ) == false)

        // Nil input
        #expect(HookProcessor.isDestructiveTool(name: "Bash", input: nil) == false)
    }
}
