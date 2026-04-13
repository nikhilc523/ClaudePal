import CloudKit
import ClaudePalMacCore
import os

private let logger = Logger(subsystem: "com.claudepal.mac", category: "CloudKitPusher")

/// Pushes local state changes to CloudKit (Mac → Cloud).
/// All errors are caught silently — CloudKit failures never block the app.
actor CloudKitPusher: CloudSyncPushing {
    private let database: CKDatabase
    private var zoneCreated = false

    init(database: CKDatabase) {
        self.database = database
    }

    // MARK: - CloudSyncPushing

    nonisolated func pushSession(_ session: Session) async {
        await ensureZone()
        await saveRecord(session.toCKRecord(), label: "session \(session.id)")
    }

    nonisolated func pushEvent(_ event: Event) async {
        await ensureZone()
        await saveRecord(event.toCKRecord(), label: "event \(event.id)")
    }

    nonisolated func pushPendingDecision(_ decision: PendingDecision) async {
        await ensureZone()
        await saveRecord(decision.toCKRecord(), label: "decision \(decision.id)")
    }

    nonisolated func pushDecisionResolution(decisionId: String, status: DecisionStatus, resolvedAt: Date) async {
        await ensureZone()
        let recordID = CKRecord.ID(recordName: decisionId, zoneID: CloudKitConfig.zoneID)
        do {
            let record = try await database.record(for: recordID)
            record["status"] = status.rawValue as CKRecordValue
            record["resolvedAt"] = resolvedAt as CKRecordValue
            await saveRecord(record, label: "decision-resolution \(decisionId)")
        } catch {
            logger.warning("Failed to fetch decision for resolution update: \(error.localizedDescription)")
        }
    }

    // MARK: - Batch Push

    func pushRecords(_ records: [CKRecord]) async {
        guard !records.isEmpty else { return }
        await ensureZone()
        do {
            _ = try await database.modifyRecords(saving: records, deleting: [], savePolicy: .changedKeys, atomically: false)
            logger.info("Batch pushed \(records.count) records")
        } catch {
            logger.warning("Batch push failed: \(error.localizedDescription)")
        }
    }

    /// Mark an approval command as processed in CloudKit.
    func markCommandProcessed(recordID: CKRecord.ID) async {
        do {
            let record = try await database.record(for: recordID)
            record["processedAt"] = Date() as CKRecordValue
            await saveRecord(record, label: "command-processed")
        } catch {
            logger.warning("Failed to mark command processed: \(error.localizedDescription)")
        }
    }

    // MARK: - Zone Management

    private func ensureZone() async {
        guard !zoneCreated else { return }
        do {
            let zone = CKRecordZone(zoneID: CloudKitConfig.zoneID)
            _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
            zoneCreated = true
            logger.info("CloudKit zone '\(CloudKitConfig.zoneName)' ready")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            zoneCreated = true
        } catch {
            logger.warning("Failed to create zone: \(error.localizedDescription)")
        }
    }

    // MARK: - Save with Retry

    private func saveRecord(_ record: CKRecord, label: String, retryCount: Int = 0) async {
        do {
            _ = try await database.modifyRecords(saving: [record], deleting: [], savePolicy: .changedKeys, atomically: false)
            logger.debug("Pushed \(label)")
        } catch let error as CKError where isRetryable(error) && retryCount < 3 {
            let delay = error.retryAfterSeconds ?? Double(retryCount + 1) * 2.0
            logger.info("Retrying \(label) in \(delay)s (attempt \(retryCount + 1))")
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            await saveRecord(record, label: label, retryCount: retryCount + 1)
        } catch {
            logger.warning("Failed to push \(label): \(error.localizedDescription)")
        }
    }

    private func isRetryable(_ error: CKError) -> Bool {
        switch error.code {
        case .networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited:
            return true
        default:
            return false
        }
    }
}
