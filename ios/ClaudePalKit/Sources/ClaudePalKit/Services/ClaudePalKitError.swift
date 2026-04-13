import Foundation

public enum ClaudePalKitError: Error, Equatable {
    case authenticationFailed
    case syncUnavailable
    case invalidPayload
    case requestFailed(statusCode: Int)
}
