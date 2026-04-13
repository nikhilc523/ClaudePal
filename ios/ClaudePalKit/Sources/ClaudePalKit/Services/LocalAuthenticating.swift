import Foundation
import LocalAuthentication

public protocol LocalAuthenticating: Sendable {
    func authenticate(reason: String) async throws
}

public final class SystemLocalAuthenticator: LocalAuthenticating, @unchecked Sendable {
    public init() {}

    public func authenticate(reason: String) async throws {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            throw error ?? ClaudePalKitError.authenticationFailed
        }

        try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
    }
}
