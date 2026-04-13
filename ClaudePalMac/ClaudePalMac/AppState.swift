import SwiftUI
import ClaudePalMacCore
import ServiceManagement
import UserNotifications

/// Central app state that owns the database, hook server, and hook config.
/// Published properties drive the SwiftUI menu bar UI.
@MainActor
final class AppState: ObservableObject {
    let db: AppDatabase
    let processor: HookProcessor
    let server: HookServer
    let hookConfig: ClaudeHookConfig
    var cloudKitManager: CloudKitManager?

    // MARK: - Core state

    @Published var sessions: [Session] = []
    @Published var pendingDecisions: [PendingDecision] = []
    @Published var serverRunning = false
    @Published var hooksInstalled = false
    @Published var launchOnLogin = false

    /// Incremented each time new pending decisions arrive — drives mascot dance.
    @Published var danceTrigger: Int = 0

    // MARK: - Feature 1: Sound Notifications

    @Published var soundPreferences: SoundPreferences

    // MARK: - Feature 2: Model Detection

    @Published var currentModel: ModelInfo?
    @Published var effortLevel: EffortLevel = .high
    let sessionFileWatcher: SessionFileWatcher

    // MARK: - Feature 3: Permission Mode

    @Published var permissionMode: PermissionMode = .normal
    let permissionManager: PermissionModeManager

    // MARK: - Feature 4: Service Status + Tokens + Usage

    @Published var serviceStatus: ClaudeServiceStatus?
    @Published var sessionTokens: SessionTokens = .zero
    @Published var usageData: ClaudeUsageData?
    @Published var hasSessionCookie: Bool = false
    let statusChecker = ServiceStatusChecker()
    let tokenTracker = LocalTokenTracker()
    let usageFetcher = ClaudeUsageFetcher()

    // MARK: - Internal

    var notchPanel: NotchPanelController?
    private var previousPendingCount = 0
    private var previousSessionStatuses: [String: SessionStatus] = [:]

    var pendingCount: Int { pendingDecisions.count }

    var statusIcon: String {
        if !serverRunning { return "exclamationmark.circle" }
        if pendingCount > 0 { return "bell.badge.fill" }
        if sessions.contains(where: { $0.status == .active }) { return "bolt.fill" }
        return "cloud.fill"
    }

    init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent("ClaudePal")

        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)

        let dbPath = appSupport.appendingPathComponent("claudepal.db").path
        let database = try! AppDatabase(path: dbPath)

        let proc = HookProcessor(db: database)

        self.db = database
        self.processor = proc
        self.server = HookServer(processor: proc)
        self.hookConfig = ClaudeHookConfig()
        self.soundPreferences = SoundPreferences.load()
        self.sessionFileWatcher = SessionFileWatcher()
        self.permissionManager = PermissionModeManager()

        // Check initial state
        self.hooksInstalled = (try? hookConfig.isInstalled()) ?? false
        self.launchOnLogin = SMAppService.mainApp.status == .enabled
        self.permissionMode = permissionManager.detectCurrentMode()
        self.effortLevel = EffortLevelReader.read()
        self.hasSessionCookie = ClaudeCookieStore.hasKey

        // Wire session file watcher callbacks
        sessionFileWatcher.onModelInfoChanged = { [weak self] info in
            Task { @MainActor in
                self?.currentModel = info
                if let usage = info?.lastUsage {
                    self?.tokenTracker.accumulate(usage: usage)
                    self?.sessionTokens = self?.tokenTracker.current ?? .zero
                }
            }
        }

        // Start everything
        Task {
            await startServer()
            startPolling()
            requestNotificationPermission()
            sessionFileWatcher.start()
            await startStatusPolling()
            await startUsagePolling()
            self.notchPanel = NotchPanelController(appState: self)
        }
    }

    // MARK: - Server

    func startServer() async {
        do {
            try await server.start()
            serverRunning = true
        } catch {
            serverRunning = false
        }
    }

    // MARK: - CloudKit (lazy init — only if iCloud is available)

    func startCloudKit() async {
        let manager = await CloudKitManager.createIfAvailable(
            db: db, hookProcessor: processor
        )
        if let manager {
            self.cloudKitManager = manager
            await manager.start()
        }
    }

    // MARK: - Hook Installation

    func installHooks() {
        do {
            try hookConfig.install()
            hooksInstalled = true
        } catch {
            hooksInstalled = false
        }
    }

    func uninstallHooks() {
        do {
            try hookConfig.uninstall()
            hooksInstalled = false
        } catch {
            // keep current state
        }
    }

    // MARK: - Launch on Login

    func toggleLaunchOnLogin() {
        do {
            if launchOnLogin {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
            launchOnLogin = SMAppService.mainApp.status == .enabled
        } catch {
            // keep current state
        }
    }

    // MARK: - Decisions

    func approve(decision: PendingDecision) {
        Task {
            try? await processor.resolve(decisionId: decision.id, approved: true)
            refresh()
        }
    }

    func deny(decision: PendingDecision) {
        Task {
            try? await processor.resolve(decisionId: decision.id, approved: false, reason: "Denied from ClaudePal")
            refresh()
        }
    }

    // MARK: - Feature 1: Sound

    func playSound(for event: SoundEventType) {
        guard !soundPreferences.isMuted else { return }
        let name = soundPreferences.soundName(for: event)
        NSSound(named: NSSound.Name(name))?.play()
    }

    func updateSoundPreferences(_ prefs: SoundPreferences) {
        soundPreferences = prefs
        prefs.save()
    }

    // MARK: - Feature 3: Permission Mode

    func setPermissionMode(_ mode: PermissionMode) {
        do {
            try permissionManager.apply(mode: mode)
            permissionMode = mode
        } catch {
            // keep current state
        }
    }

    // MARK: - Feature 4: Service Status + Usage

    private func startStatusPolling() async {
        await statusChecker.startPolling(interval: 60) { [weak self] status in
            Task { @MainActor in
                self?.serviceStatus = status
            }
        }
    }

    private func startUsagePolling() async {
        guard hasSessionCookie else { return }
        await refreshUsage()
        // Poll every 5 minutes
        Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshUsage()
            }
        }
    }

    func refreshUsage() async {
        let data = await usageFetcher.fetchUsage()
        usageData = data
    }

    func setSessionCookie(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let saved = ClaudeCookieStore.save(sessionKey: trimmed)
        hasSessionCookie = saved
        if saved {
            Task { await startUsagePolling() }
        }
    }

    func clearSessionCookie() {
        ClaudeCookieStore.delete()
        hasSessionCookie = false
        usageData = nil
    }

    // MARK: - Polling

    /// Simple polling loop to refresh state from the database.
    func startPolling() {
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func refresh() {
        let oldSessions = sessions
        sessions = (try? db.fetchAllSessions()) ?? []

        // Expire stale decisions before fetching
        _ = try? db.expireStaleDecisions()
        let newPending = (try? db.fetchPendingDecisions()) ?? []

        // Detect new pending decisions → play permission prompt sound
        if newPending.count > previousPendingCount && previousPendingCount >= 0 {
            let newOnes = newPending.filter { newD in
                !pendingDecisions.contains(where: { $0.id == newD.id })
            }
            if !newOnes.isEmpty {
                playSound(for: .permissionPrompt)
                sendDesktopNotification(for: newOnes)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.danceTrigger += 1
                }
            }
        }

        // Detect task completions → play completion sound
        for session in sessions {
            if session.status == .completed,
               let old = oldSessions.first(where: { $0.id == session.id }),
               old.status != .completed {
                playSound(for: .taskCompletion)
                break
            }
        }

        previousPendingCount = newPending.count
        pendingDecisions = newPending

        // Refresh permission mode periodically (cheap read)
        permissionMode = permissionManager.detectCurrentMode()
    }

    // MARK: - Desktop Notifications

    func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }

        // Register actionable notification categories
        let approveAction = UNNotificationAction(
            identifier: "APPROVE_ACTION",
            title: "✓ Approve",
            options: []
        )
        let denyAction = UNNotificationAction(
            identifier: "DENY_ACTION",
            title: "✗ Deny",
            options: [.destructive]
        )
        let approvalCategory = UNNotificationCategory(
            identifier: "APPROVAL",
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )
        let destructiveCategory = UNNotificationCategory(
            identifier: "DESTRUCTIVE_APPROVAL",
            actions: [approveAction, denyAction],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([approvalCategory, destructiveCategory])
    }

    private func sendDesktopNotification(for decisions: [PendingDecision]) {
        let center = UNUserNotificationCenter.current()

        for decision in decisions.prefix(3) {
            let content = UNMutableNotificationContent()

            let toolName = decision.toolName ?? "Unknown"

            if decision.isDestructive {
                content.title = "⚠️ Destructive Action — \(toolName)"
                content.categoryIdentifier = "DESTRUCTIVE_APPROVAL"
            } else {
                content.title = "🔒 Permission Request — \(toolName)"
                content.categoryIdentifier = "APPROVAL"
            }

            // Build a rich body
            var bodyLines: [String] = []

            if let input = decision.toolInput,
               let data = input.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let cmd = json["command"] as? String {
                    bodyLines.append("$ \(cmd)")
                } else if let filePath = json["file_path"] as? String {
                    bodyLines.append("📄 \(filePath)")
                } else if let pattern = json["pattern"] as? String {
                    bodyLines.append("🔍 \(pattern)")
                }
            }

            // Add session context
            if let session = sessions.first(where: { $0.id == decision.sessionId }) {
                bodyLines.append("📁 \(session.displayName)")
            }

            content.body = bodyLines.joined(separator: "\n")
            content.sound = .default

            // Store decision ID for action handling
            content.userInfo = ["decisionId": decision.id]

            let request = UNNotificationRequest(
                identifier: decision.id,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
