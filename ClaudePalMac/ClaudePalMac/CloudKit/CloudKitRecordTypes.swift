import CloudKit
import ClaudePalMacCore

/// Constants and CKRecord mapping for CloudKit sync.
enum CloudKitConfig {
    static let containerID = "iCloud.com.claudepal.sync"
    static let zoneName = "ClaudePalZone"
    static let zoneID = CKRecordZone.ID(zoneName: zoneName)

    enum RecordType {
        static let session = "CPSession"
        static let event = "CPEvent"
        static let pendingDecision = "CPPendingDecision"
        static let approvalCommand = "CPApprovalCommand"
        static let deviceRegistration = "CPDeviceRegistration"
    }

    /// Subscription IDs
    enum SubscriptionID {
        static let databaseChanges = "claudepal-db-changes"
    }
}

// MARK: - Session <-> CKRecord

extension Session {
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: CloudKitConfig.zoneID)
        let record = CKRecord(recordType: CloudKitConfig.RecordType.session, recordID: recordID)
        record["sessionId"] = id as CKRecordValue
        record["cwd"] = cwd as CKRecordValue
        record["displayName"] = displayName as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        record["startedAt"] = startedAt as CKRecordValue
        record["updatedAt"] = updatedAt as CKRecordValue
        return record
    }

    init?(from record: CKRecord) {
        guard record.recordType == CloudKitConfig.RecordType.session,
              let sessionId = record["sessionId"] as? String,
              let cwd = record["cwd"] as? String,
              let displayName = record["displayName"] as? String,
              let statusRaw = record["status"] as? String,
              let status = SessionStatus(rawValue: statusRaw),
              let startedAt = record["startedAt"] as? Date,
              let updatedAt = record["updatedAt"] as? Date else {
            return nil
        }
        self.init(id: sessionId, cwd: cwd, displayName: displayName,
                  status: status, startedAt: startedAt, updatedAt: updatedAt)
    }
}

// MARK: - Event <-> CKRecord

extension Event {
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: CloudKitConfig.zoneID)
        let record = CKRecord(recordType: CloudKitConfig.RecordType.event, recordID: recordID)
        record["eventId"] = id as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["type"] = type.rawValue as CKRecordValue
        record["title"] = title as CKRecordValue
        record["message"] = message as CKRecordValue
        record["payload"] = payload as CKRecordValue?
        record["createdAt"] = createdAt as CKRecordValue
        return record
    }
}

// MARK: - PendingDecision <-> CKRecord

extension PendingDecision {
    func toCKRecord() -> CKRecord {
        let recordID = CKRecord.ID(recordName: id, zoneID: CloudKitConfig.zoneID)
        let record = CKRecord(recordType: CloudKitConfig.RecordType.pendingDecision, recordID: recordID)
        record["decisionId"] = id as CKRecordValue
        record["sessionId"] = sessionId as CKRecordValue
        record["eventId"] = eventId as CKRecordValue
        record["status"] = status.rawValue as CKRecordValue
        record["toolName"] = toolName as CKRecordValue?
        record["toolInput"] = toolInput as CKRecordValue?
        record["isDestructive"] = (isDestructive ? 1 : 0) as CKRecordValue
        record["expiresAt"] = expiresAt as CKRecordValue
        record["resolvedAt"] = resolvedAt as CKRecordValue?
        record["createdAt"] = createdAt as CKRecordValue
        return record
    }
}

// MARK: - ApprovalCommand (CloudKit-only)

/// Represents an approval command sent by iPhone/Watch via CloudKit.
/// This struct has no local DB representation — it exists only in CloudKit.
struct ApprovalCommand: Sendable {
    let commandId: String
    let pendingDecisionId: String
    let action: String          // "approve" or "deny"
    let reason: String?
    let sourceDevice: String    // "iphone" or "watch"
    let createdAt: Date
    let processedAt: Date?

    init?(from record: CKRecord) {
        guard record.recordType == CloudKitConfig.RecordType.approvalCommand,
              let commandId = record["commandId"] as? String,
              let pendingDecisionId = record["pendingDecisionId"] as? String,
              let action = record["action"] as? String,
              let sourceDevice = record["sourceDevice"] as? String,
              let createdAt = record["createdAt"] as? Date else {
            return nil
        }
        self.commandId = commandId
        self.pendingDecisionId = pendingDecisionId
        self.action = action
        self.reason = record["reason"] as? String
        self.sourceDevice = sourceDevice
        self.createdAt = createdAt
        self.processedAt = record["processedAt"] as? Date
    }

    /// Whether this command has already been processed.
    var isProcessed: Bool { processedAt != nil }
}
