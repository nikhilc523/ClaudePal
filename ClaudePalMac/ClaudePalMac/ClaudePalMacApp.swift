import SwiftUI
import ClaudePalMacCore

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

// MARK: - App Delegate (for remote notifications)

class AppDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

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
