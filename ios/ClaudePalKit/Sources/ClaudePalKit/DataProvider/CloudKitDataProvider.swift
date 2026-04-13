import Foundation
#if canImport(Observation)
import Observation
#endif

/// CloudKit-backed data provider. Stub implementation — will be wired
/// to CKDatabase once developer account + entitlements are configured.
@available(iOS 17.0, watchOS 10.0, macOS 14.0, *)
@MainActor @Observable
public final class CloudKitDataProvider: DataProvider {
    public var sessions: [Session] = []
    public var pendingDecisions: [PendingDecision] = []
    public var recentEvents: [Event] = []
    public var connectionState: ConnectionState = .disconnected

    // TODO: CloudKit constants (must match macOS CloudKitConfig)
    // static let containerID = "iCloud.com.claudepal.sync"
    // static let zoneName = "ClaudePalZone"

    public init() {}

    public func start() async {
        // TODO: Check CKContainer.accountStatus()
        // TODO: Subscribe to CPPendingDecision and CPSession changes
        // TODO: Fetch initial state
        connectionState = .disconnected
    }

    public func refresh() async {
        // TODO: CKFetchRecordZoneChangesOperation
    }

    public func approve(decisionId: String) async throws {
        // TODO: Write CPApprovalCommand to CloudKit with action = "approve"
        throw CloudKitDataProviderError.notImplemented
    }

    public func deny(decisionId: String, reason: String?) async throws {
        // TODO: Write CPApprovalCommand to CloudKit with action = "deny"
        throw CloudKitDataProviderError.notImplemented
    }

    public func events(for sessionId: String) -> [Event] {
        recentEvents.filter { $0.sessionId == sessionId }
    }
}

enum CloudKitDataProviderError: Error {
    case notImplemented
}
