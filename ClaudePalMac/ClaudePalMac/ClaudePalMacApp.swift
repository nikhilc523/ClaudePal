import SwiftUI
import ClaudePalMacCore
import UserNotifications

@main
struct ClaudePalMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        // No MenuBarExtra — the notch panel is the primary UI.
        Settings {
            EmptyView()
        }
        .onChange(of: appState.cloudKitManager != nil) {
            appDelegate.appState = appState
        }
    }
}

// MARK: - App Delegate (for remote + local notifications)

class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    weak var appState: AppState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UNUserNotificationCenter.current().delegate = self
    }

    // MARK: - Local notification actions (Approve / Deny from banner)

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        guard let decisionId = userInfo["decisionId"] as? String else {
            completionHandler()
            return
        }

        Task { @MainActor in
            guard let appState = self.appState else {
                completionHandler()
                return
            }
            guard let decision = appState.pendingDecisions.first(where: { $0.id == decisionId }) else {
                completionHandler()
                return
            }

            switch response.actionIdentifier {
            case "APPROVE_ACTION":
                appState.approve(decision: decision)
            case "DENY_ACTION":
                appState.deny(decision: decision)
            default:
                // Tapped the notification itself — expand the panel
                appState.notchPanel?.expand()
            }
            completionHandler()
        }
    }

    // MARK: - Show notifications even when app is foreground

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    // MARK: - Remote notifications (CloudKit)

    func application(_ application: NSApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    }

    func application(_ application: NSApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
    }

    func application(_ application: NSApplication,
                     didReceiveRemoteNotification userInfo: [String: Any]) {
        guard let manager = appState?.cloudKitManager else { return }
        Task {
            await manager.handleRemoteNotification(userInfo: userInfo)
        }
    }
}
