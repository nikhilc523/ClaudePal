import Foundation

/// Connection state for sync layer.
public enum ConnectionState: Equatable, Sendable {
    case connected
    case syncing
    case disconnected
    case error(String)

    public var displayText: String {
        switch self {
        case .connected: "Connected"
        case .syncing: "Syncing..."
        case .disconnected: "Disconnected"
        case .error(let msg): "Error: \(msg)"
        }
    }

    public var isConnected: Bool {
        switch self {
        case .connected, .syncing: true
        default: false
        }
    }
}

/// Protocol for providing app data. Concrete implementations:
/// - `MockDataProvider` for development/previews
/// - `CloudKitDataProvider` for production (wired to CloudKit)
@MainActor
public protocol DataProvider: AnyObject {
    var sessions: [Session] { get }
    var pendingDecisions: [PendingDecision] { get }
    var recentEvents: [Event] { get }
    var connectionState: ConnectionState { get }

    func start() async
    func refresh() async
    func approve(decisionId: String) async throws
    func deny(decisionId: String, reason: String?) async throws
    func events(for sessionId: String) -> [Event]
}
