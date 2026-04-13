import AppKit
import CloudKit
import ClaudePalMacCore
import os

private let logger = Logger(subsystem: "com.claudepal.mac", category: "CloudKitManager")

/// Top-level coordinator for CloudKit sync.
/// Owns the pusher, subscription handler, and command processor.
/// Created lazily via `createIfAvailable()` — only when iCloud is accessible.
@MainActor
final class CloudKitManager {
    let pusher: CloudKitPusher
    private let subscriptionHandler: CloudKitSubscriptionHandler
    private let commandProcessor: ApprovalCommandProcessor
    private let container: CKContainer
    private let database: CKDatabase
    private let db: AppDatabase
    private var pollTimer: Timer?
    private(set) var isAvailable = false

    /// Factory: only creates a CloudKitManager if iCloud is available.
    /// Returns nil if CloudKit cannot be used (no entitlements, signed out, etc.).
    static func createIfAvailable(db: AppDatabase, hookProcessor: HookProcessor) async -> CloudKitManager? {
        // Try creating CKContainer — this will crash without entitlements,
        // so we check for the entitlement first.
        guard hasCloudKitEntitlement() else {
            logger.info("CloudKit entitlement not found, sync disabled (add developer account to enable)")
            return nil
        }

        let container = CKContainer(identifier: CloudKitConfig.containerID)
        do {
            let status = try await container.accountStatus()
            guard status == .available else {
                logger.info("iCloud not available (status: \(String(describing: status))), sync disabled")
                return nil
            }
        } catch {
            logger.warning("Failed to check iCloud: \(error.localizedDescription), sync disabled")
            return nil
        }

        let pusher = CloudKitPusher(database: container.privateCloudDatabase)
        return CloudKitManager(
            db: db, hookProcessor: hookProcessor,
            pusher: pusher, container: container
        )
    }

    /// Check if the app has CloudKit entitlements by looking at the code signature.
    private static func hasCloudKitEntitlement() -> Bool {
        // Check if the entitlements plist includes iCloud services.
        // If CKContainer init would crash, we catch it here first.
        guard let infoPlist = Bundle.main.infoDictionary else { return false }
        // A more reliable check: try to access the default container (won't crash).
        // If the app has no CloudKit entitlement at all, accountStatus will fail gracefully.
        // The crash only happens with CKContainer(identifier:) for a specific container
        // that's not in the entitlements. Use default() as a safe check.
        let defaultContainer = CKContainer.default()
        // If defaultContainer.containerIdentifier is nil or empty, CloudKit isn't configured
        return defaultContainer.containerIdentifier != nil
    }

    private init(db: AppDatabase, hookProcessor: HookProcessor, pusher: CloudKitPusher, container: CKContainer) {
        self.db = db
        self.container = container
        self.database = container.privateCloudDatabase
        self.pusher = pusher
        self.commandProcessor = ApprovalCommandProcessor(
            db: db, hookProcessor: hookProcessor, pusher: pusher
        )
        self.subscriptionHandler = CloudKitSubscriptionHandler(
            database: database, commandProcessor: commandProcessor
        )
    }

    // MARK: - Start

    func start() async {
        isAvailable = true
        logger.info("CloudKit sync starting")

        // Set up subscription for incoming commands
        await subscriptionHandler.setupSubscription()

        // Register for remote notifications
        NSApplication.shared.registerForRemoteNotifications()

        // Sync existing pending decisions to CloudKit
        await syncExistingState()

        // Start polling fallback (catches missed push notifications)
        startPolling()

        // Listen for account changes
        NotificationCenter.default.addObserver(
            forName: .CKAccountChanged, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.handleAccountChange()
            }
        }

        logger.info("CloudKit sync started")
    }

    // MARK: - Remote Notification

    func handleRemoteNotification(userInfo: [AnyHashable: Any]) async {
        guard isAvailable else { return }
        let notification = CKNotification(fromRemoteNotificationDictionary: userInfo)
        if notification?.subscriptionID == CloudKitConfig.SubscriptionID.databaseChanges {
            await subscriptionHandler.handleNotification()
        }
    }

    // MARK: - Sync Existing State

    private func syncExistingState() async {
        guard let pending = try? db.fetchPendingDecisions() else { return }
        guard !pending.isEmpty else { return }

        let records = pending.map { $0.toCKRecord() }
        await pusher.pushRecords(records)
        logger.info("Synced \(pending.count) existing pending decisions to CloudKit")
    }

    // MARK: - Polling Fallback

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.pollForCommands()
            }
        }
    }

    private func pollForCommands() async {
        guard isAvailable else { return }
        await subscriptionHandler.handleNotification()
    }

    // MARK: - Account Changes

    private func handleAccountChange() async {
        do {
            let status = try await container.accountStatus()
            let wasAvailable = isAvailable
            isAvailable = status == .available

            if isAvailable && !wasAvailable {
                logger.info("iCloud became available, restarting sync")
                await subscriptionHandler.setupSubscription()
                await syncExistingState()
            } else if !isAvailable && wasAvailable {
                logger.info("iCloud became unavailable, pausing sync")
            }
        } catch {
            logger.warning("Failed to check account after change: \(error.localizedDescription)")
        }
    }
}
