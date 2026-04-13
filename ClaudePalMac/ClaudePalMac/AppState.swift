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

    // MARK: - Feature 4: Service Status + Tokens

    @Published var serviceStatus: ClaudeServiceStatus?
    @Published var sessionTokens: SessionTokens = .zero
    let statusChecker = ServiceStatusChecker()
    let tokenTracker = LocalTokenTracker()

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

    // MARK: - Feature 4: Service Status

    private func startStatusPolling() async {
        await statusChecker.startPolling(interval: 60) { [weak self] status in
            Task { @MainActor in
                self?.serviceStatus = status
            }
        }
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
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    private func sendDesktopNotification(for decisions: [PendingDecision]) {
        let center = UNUserNotificationCenter.current()

        for decision in decisions.prefix(3) {
            let content = UNMutableNotificationContent()
            content.title = decision.isDestructive ? "Destructive Action" : "Approval Needed"
            content.subtitle = decision.toolName ?? "Unknown Tool"

            if let input = decision.toolInput,
               let data = input.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let cmd = json["command"] as? String ?? json["file_path"] as? String {
                content.body = cmd
            } else {
                content.body = String((decision.toolInput ?? "").prefix(80))
            }

            content.sound = .default
            content.categoryIdentifier = "APPROVAL"

            let request = UNNotificationRequest(
                identifier: decision.id,
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}
