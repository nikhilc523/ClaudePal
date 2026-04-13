import Foundation
import SwiftUI

/// Placeholder Watch connectivity — will be rewired for CloudKit sync.
@MainActor
final class WatchConnectivityController: NSObject, ObservableObject {
    static let shared = WatchConnectivityController()

    @Published var pendingCount = 0
    @Published var sessionName: String?
    @Published var sessionStatus: String = "idle"
    @Published var statusMessage = "Connecting..."

    private override init() {
        super.init()
    }

    func requestSync() {
        statusMessage = "Sync not yet available — CloudKit coming soon."
    }
}
