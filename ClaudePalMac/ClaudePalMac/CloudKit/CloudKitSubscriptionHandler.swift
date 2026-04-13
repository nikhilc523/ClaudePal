import CloudKit
import os

private let logger = Logger(subsystem: "com.claudepal.mac", category: "CloudKitSubscriptions")

/// Handles CloudKit database subscriptions and processes incoming changes.
/// Listens for CPApprovalCommand records written by iPhone/Watch.
actor CloudKitSubscriptionHandler {
    private let database: CKDatabase
    private let commandProcessor: ApprovalCommandProcessor
    private let changeTokenKey = "CloudKitServerChangeToken"

    init(database: CKDatabase, commandProcessor: ApprovalCommandProcessor) {
        self.database = database
        self.commandProcessor = commandProcessor
    }

    // MARK: - Setup

    /// Create a database subscription for the custom zone (idempotent).
    func setupSubscription() async {
        let subscription = CKDatabaseSubscription(subscriptionID: CloudKitConfig.SubscriptionID.databaseChanges)
        let notificationInfo = CKSubscription.NotificationInfo()
        notificationInfo.shouldSendContentAvailable = true // silent push
        subscription.notificationInfo = notificationInfo

        do {
            _ = try await database.modifySubscriptions(saving: [subscription], deleting: [])
            logger.info("CloudKit subscription ready")
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Subscription might already exist — fine
            logger.debug("Subscription already exists")
        } catch {
            logger.warning("Failed to create subscription: \(error.localizedDescription)")
        }
    }

    // MARK: - Handle Notification

    /// Called when a remote notification arrives. Fetches changes from CloudKit.
    func handleNotification() async {
        await fetchDatabaseChanges()
    }

    // MARK: - Fetch Changes

    /// Fetch database changes since last server change token.
    private func fetchDatabaseChanges() async {
        let previousToken = loadChangeToken()

        do {
            // Fetch changed zone IDs
            let changes = try await database.recordZoneChanges(
                inZoneWith: CloudKitConfig.zoneID,
                since: previousToken
            )

            // Process modifications
            for modification in changes.modificationResultsByID {
                let (recordID, result) = modification
                switch result {
                case .success(let modificationResult):
                    let record = modificationResult.record
                    if record.recordType == CloudKitConfig.RecordType.approvalCommand {
                        if let command = ApprovalCommand(from: record) {
                            await commandProcessor.processCommand(command, recordID: recordID)
                        }
                    }
                case .failure(let error):
                    logger.warning("Failed to fetch record \(recordID): \(error.localizedDescription)")
                }
            }

            // Save the new change token
            saveChangeToken(changes.changeToken)

            logger.debug("Processed \(changes.modificationResultsByID.count) CloudKit changes")
        } catch {
            logger.warning("Failed to fetch database changes: \(error.localizedDescription)")
        }
    }

    // MARK: - Change Token Persistence

    private func loadChangeToken() -> CKServerChangeToken? {
        guard let data = UserDefaults.standard.data(forKey: changeTokenKey) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func saveChangeToken(_ token: CKServerChangeToken) {
        guard let data = try? NSKeyedArchiver.archivedData(
            withRootObject: token, requiringSecureCoding: true
        ) else { return }
        UserDefaults.standard.set(data, forKey: changeTokenKey)
    }
}
