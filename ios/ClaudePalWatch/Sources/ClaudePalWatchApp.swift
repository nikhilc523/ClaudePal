import SwiftUI

@main
struct ClaudePalWatchApp: App {
    @StateObject private var connectivityController = WatchConnectivityController.shared

    var body: some Scene {
        WindowGroup {
            WatchRootView(controller: connectivityController)
        }
    }
}
