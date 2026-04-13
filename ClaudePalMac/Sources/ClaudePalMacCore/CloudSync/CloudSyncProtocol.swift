import Foundation

/// Protocol for pushing local state changes to a cloud sync layer.
/// The concrete implementation (CloudKit) lives in the app target.
/// This protocol lives in Core so HookProcessor can reference it without importing CloudKit.
public protocol CloudSyncPushing: Sendable {
    func pushSession(_ session: Session) async
    func pushEvent(_ event: Event) async
    func pushPendingDecision(_ decision: PendingDecision) async
    func pushDecisionResolution(decisionId: String, status: DecisionStatus, resolvedAt: Date) async
}
