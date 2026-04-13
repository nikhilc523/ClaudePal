#if canImport(ActivityKit) && os(iOS)
import ActivityKit
import Foundation

@available(iOS 17.0, *)
public struct ClaudePalActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        public let status: String
        public let pendingApprovals: Int
        public let detail: String
        public let updatedAt: Date

        public init(status: String, pendingApprovals: Int, detail: String, updatedAt: Date) {
            self.status = status
            self.pendingApprovals = pendingApprovals
            self.detail = detail
            self.updatedAt = updatedAt
        }
    }

    public let sessionID: String
    public let displayName: String

    public init(sessionID: String, displayName: String) {
        self.sessionID = sessionID
        self.displayName = displayName
    }
}
#endif
