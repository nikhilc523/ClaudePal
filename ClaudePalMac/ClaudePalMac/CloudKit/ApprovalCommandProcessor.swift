import CloudKit
import ClaudePalMacCore
import os

private let logger = Logger(subsystem: "com.claudepal.mac", category: "ApprovalCommandProcessor")

/// Processes incoming approval commands from CloudKit (written by iPhone/Watch).
/// Validates the command, resolves the decision locally, and mirrors the result back.
actor ApprovalCommandProcessor {
    private let db: AppDatabase
    private let hookProcessor: HookProcessor
    private let pusher: CloudKitPusher

    init(db: AppDatabase, hookProcessor: HookProcessor, pusher: CloudKitPusher) {
        self.db = db
        self.hookProcessor = hookProcessor
        self.pusher = pusher
    }

    /// Process a single approval command from CloudKit.
    func processCommand(_ command: ApprovalCommand, recordID: CKRecord.ID) async {
        // Skip already processed commands
        guard !command.isProcessed else {
            logger.debug("Skipping already processed command \(command.commandId)")
            return
        }

        // 1. Validate: does the pending decision exist?
        guard let decision = try? db.fetchPendingDecision(id: command.pendingDecisionId) else {
            logger.warning("Command \(command.commandId) references unknown decision \(command.pendingDecisionId)")
            await pusher.markCommandProcessed(recordID: recordID)
            return
        }

        // 2. Is it still pending?
        guard decision.status == .pending else {
            logger.info("Decision \(command.pendingDecisionId) already resolved (\(decision.status.rawValue)), skipping command")
            await pusher.markCommandProcessed(recordID: recordID)
            return
        }

        // 3. Validate action
        let approved: Bool
        switch command.action {
        case "approve":
            approved = true
        case "deny":
            approved = false
        default:
            logger.warning("Unknown action '\(command.action)' in command \(command.commandId)")
            await pusher.markCommandProcessed(recordID: recordID)
            return
        }

        // 4. Resolve locally (writes to DB and yields into the AsyncStream)
        do {
            try await hookProcessor.resolve(
                decisionId: command.pendingDecisionId,
                approved: approved,
                reason: command.reason ?? "Approved from \(command.sourceDevice)"
            )
            logger.info("Resolved decision \(command.pendingDecisionId) via \(command.sourceDevice): \(command.action)")
        } catch {
            logger.error("Failed to resolve decision \(command.pendingDecisionId): \(error.localizedDescription)")
        }

        // 5. Mark command as processed in CloudKit
        await pusher.markCommandProcessed(recordID: recordID)
    }
}
