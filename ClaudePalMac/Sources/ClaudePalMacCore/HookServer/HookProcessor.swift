import Foundation

/// Processes incoming Claude Code hook payloads:
/// - creates/updates sessions, events, and pending decisions in storage
/// - for permission hooks, waits asynchronously for a decision (from mobile or local UI)
/// - returns the appropriate hook response to Claude Code
public actor HookProcessor {
    private let db: AppDatabase
    private let defaultTimeoutSeconds: TimeInterval
    private let pusher: (any CloudSyncPushing)?

    /// Active decision channels. Key is the pending decision ID.
    /// resolve() yields into the continuation; processPermissionRequest awaits the stream.
    private var waitingDecisions: [String: AsyncStream<HookDecisionResponse>.Continuation] = [:]

    public init(db: AppDatabase, pusher: (any CloudSyncPushing)? = nil, defaultTimeoutSeconds: TimeInterval = 120) {
        self.db = db
        self.pusher = pusher
        self.defaultTimeoutSeconds = defaultTimeoutSeconds
    }

    // MARK: - Process Hook

    /// Process an incoming hook payload.
    /// For PreToolUse (permission), this suspends until a decision arrives or timeout.
    /// For other hook types, this returns immediately.
    public func process(_ payload: HookPayload) async throws -> HookDecisionResponse? {
        // Ensure session exists
        try await ensureSession(for: payload)

        switch payload.hookType {
        case .preToolUse:
            // Monitoring only — no pending decisions for auto-approved tools
            try await processPreToolUse(payload)
            return HookDecisionResponse.allow
        case .permissionRequest:
            // Claude is actually waiting for user approval
            return try await processPermissionRequest(payload)
        case .notification:
            try await processNotification(payload)
            return nil
        case .postToolUse:
            try await processPostToolUse(payload)
            return nil
        case .stop:
            try await processStop(payload)
            return nil
        }
    }

    // MARK: - Resolve Decision (called from mobile or local UI)

    /// Resolve a pending decision. Yields the response into the waiting stream.
    public func resolve(decisionId: String, approved: Bool, reason: String? = nil) async throws {
        let status: DecisionStatus = approved ? .approved : .denied
        try db.resolveDecision(id: decisionId, status: status)

        await pusher?.pushDecisionResolution(
            decisionId: decisionId, status: status, resolvedAt: Date()
        )

        if let continuation = waitingDecisions.removeValue(forKey: decisionId) {
            let response = approved
                ? HookDecisionResponse.allow
                : HookDecisionResponse.deny(reason: reason)
            continuation.yield(response)
            continuation.finish()
        }
    }

    /// Cancel a waiting decision (e.g., on shutdown).
    public func cancelAll() {
        for (id, continuation) in waitingDecisions {
            continuation.yield(HookDecisionResponse.deny(reason: "Bridge shutting down"))
            continuation.finish()
            waitingDecisions.removeValue(forKey: id)
        }
    }

    /// Get count of currently waiting decisions (useful for health/diagnostics).
    public var activeWaitCount: Int {
        waitingDecisions.count
    }


    // MARK: - PreToolUse (monitoring only)

    /// Fires for ALL tool uses (including auto-approved). Just log, no decisions.
    private func processPreToolUse(_ payload: HookPayload) async throws {
        let toolName = payload.event.toolName ?? "Unknown"
        let event = Event(
            sessionId: payload.sessionId,
            type: .sessionUpdated,
            title: "Tool started: \(toolName)",
            message: payload.event.toolInput?.toJSONString() ?? ""
        )
        try db.saveEvent(event)
        try db.updateSessionStatus(id: payload.sessionId, status: .active)
    }

    // MARK: - Permission Request (only fires when Claude needs approval)

    private func processPermissionRequest(_ payload: HookPayload) async throws -> HookDecisionResponse {
        let toolName = payload.event.toolName ?? "Unknown"

        let eventId = UUID().uuidString
        let decisionId = UUID().uuidString
        let toolInput = payload.event.toolInput?.toJSONString()
        let isDestructive = Self.isDestructiveTool(name: toolName, input: payload.event.toolInput)

        let event = Event(
            id: eventId,
            sessionId: payload.sessionId,
            type: .permissionRequested,
            title: "\(toolName)",
            message: toolInput ?? "No input",
            payload: toolInput
        )
        try db.saveEvent(event)
        await pusher?.pushEvent(event)

        let expiresAt = Date().addingTimeInterval(defaultTimeoutSeconds)
        let decision = PendingDecision(
            id: decisionId,
            sessionId: payload.sessionId,
            eventId: eventId,
            toolName: toolName,
            toolInput: toolInput,
            isDestructive: isDestructive,
            expiresAt: expiresAt
        )
        try db.savePendingDecision(decision)
        await pusher?.pushPendingDecision(decision)

        // Create a stream for this decision. The continuation is stored synchronously
        // on the actor before we ever suspend, so resolve() can never fire too early.
        let stream = AsyncStream<HookDecisionResponse> { continuation in
            self.waitingDecisions[decisionId] = continuation
        }

        // Wait for decision or timeout.
        do {
            return try await withTimeout(seconds: defaultTimeoutSeconds) {
                for await response in stream {
                    return response
                }
                throw HookTimeoutError.timedOut
            }
        } catch is HookTimeoutError {
            // Mark the decision as expired so it doesn't stay "pending" forever
            try? db.resolveDecision(id: decisionId, status: .expired)
            waitingDecisions.removeValue(forKey: decisionId)
            throw HookTimeoutError.timedOut
        }
    }

    // MARK: - Notification

    private func processNotification(_ payload: HookPayload) async throws {
        let event = Event(
            sessionId: payload.sessionId,
            type: .notificationReceived,
            title: payload.event.title ?? "Notification",
            message: payload.event.message ?? ""
        )
        try db.saveEvent(event)
        await pusher?.pushEvent(event)
    }

    // MARK: - Post Tool Use

    private func processPostToolUse(_ payload: HookPayload) async throws {
        let toolName = payload.event.toolName ?? "Unknown"

        let event = Event(
            sessionId: payload.sessionId,
            type: .sessionUpdated,
            title: "Tool completed: \(toolName)",
            message: ""
        )
        try db.saveEvent(event)
        await pusher?.pushEvent(event)

        // Auto-resolve any pending decisions for this session+tool.
        try db.autoResolvePendingDecisions(sessionId: payload.sessionId, toolName: toolName)

        try db.updateSessionStatus(id: payload.sessionId, status: .active)
    }

    // MARK: - Stop

    private func processStop(_ payload: HookPayload) async throws {
        let event = Event(
            sessionId: payload.sessionId,
            type: .taskCompleted,
            title: "Session stopped",
            message: payload.event.message ?? ""
        )
        try db.saveEvent(event)
        await pusher?.pushEvent(event)

        try db.updateSessionStatus(id: payload.sessionId, status: .completed)
    }

    // MARK: - Session Management

    private func ensureSession(for payload: HookPayload) async throws {
        if try db.fetchSession(id: payload.sessionId) == nil {
            let cwd = payload.event.cwd ?? "unknown"
            let displayName = URL(fileURLWithPath: cwd).lastPathComponent
            let session = Session(
                id: payload.sessionId,
                cwd: cwd,
                displayName: displayName
            )
            try db.saveSession(session)
            await pusher?.pushSession(session)
        }

        // Update session to waiting if this is a permission request
        if payload.hookType == .permissionRequest {
            try db.updateSessionStatus(id: payload.sessionId, status: .waiting)
        }
    }

    // MARK: - Destructive Detection

    static func isDestructiveTool(name: String, input: JSONObject?) -> Bool {
        let destructiveTools = ["Bash"]
        guard destructiveTools.contains(name) else { return false }

        guard let input = input,
              case .string(let command) = input.values["command"] else {
            return false
        }

        let destructivePatterns = [
            "rm ", "rm\t", "rmdir",
            "git reset --hard",
            "git push --force", "git push -f",
            "drop table", "drop database",
            "truncate ",
            "> /dev/", "dd if=",
        ]

        let lower = command.lowercased()
        return destructivePatterns.contains { lower.contains($0) }
    }
}

// MARK: - Timeout Helper

enum HookTimeoutError: Error {
    case timedOut
}

func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            throw HookTimeoutError.timedOut
        }

        guard let result = try await group.next() else {
            throw HookTimeoutError.timedOut
        }
        group.cancelAll()
        return result
    }
}
