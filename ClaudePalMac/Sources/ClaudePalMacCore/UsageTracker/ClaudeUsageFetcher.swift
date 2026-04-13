import Foundation
import Security

// MARK: - Usage Data

public struct ClaudeUsageData: Equatable, Sendable {
    public let planType: String              // "pro", "max_5x", "max_20x", "free"
    public let sessionPercentUsed: Double    // 0.0 - 1.0 (5-hour window)
    public let sessionResetSeconds: Int      // seconds until 5-hour window resets
    public let weeklyPercentUsed: Double     // 0.0 - 1.0 (7-day window, if available)
    public let weeklyResetSeconds: Int       // seconds until weekly resets

    public init(planType: String, sessionPercentUsed: Double, sessionResetSeconds: Int,
                weeklyPercentUsed: Double, weeklyResetSeconds: Int) {
        self.planType = planType
        self.sessionPercentUsed = sessionPercentUsed
        self.sessionResetSeconds = sessionResetSeconds
        self.weeklyPercentUsed = weeklyPercentUsed
        self.weeklyResetSeconds = weeklyResetSeconds
    }

    // MARK: - Formatting

    public var sessionPercentText: String {
        "\(Int(sessionPercentUsed * 100))%"
    }

    public var sessionCountdownText: String {
        formatCountdown(sessionResetSeconds)
    }

    public var weeklyPercentText: String {
        "\(Int(weeklyPercentUsed * 100))%"
    }

    public var weeklyCountdownText: String {
        formatCountdown(weeklyResetSeconds)
    }

    private func formatCountdown(_ totalSeconds: Int) -> String {
        if totalSeconds <= 0 { return "now" }
        let h = totalSeconds / 3600
        let m = (totalSeconds % 3600) / 60
        if h > 24 {
            let d = h / 24
            let rh = h % 24
            return "\(d)d \(rh)h"
        }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Cookie Storage (Keychain)

public struct ClaudeCookieStore {
    private static let service = "com.claudepal.session"
    private static let account = "sessionKey"

    public static func save(sessionKey: String) -> Bool {
        // Delete existing
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        // Add new
        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: sessionKey.data(using: .utf8)!,
        ]
        return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
    }

    public static func load() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    public static func delete() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    public static var hasKey: Bool {
        load() != nil
    }
}

// MARK: - Usage Fetcher

public actor ClaudeUsageFetcher {

    private let baseURL = "https://claude.ai/api/auth/usage"

    public init() {}

    /// Fetch usage data using the stored session cookie.
    public func fetchUsage() async -> ClaudeUsageData? {
        guard let sessionKey = ClaudeCookieStore.load() else { return nil }

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "GET"
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 10

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else { return nil }
            return parseUsage(data: data)
        } catch {
            return nil
        }
    }

    private func parseUsage(data: Data) -> ClaudeUsageData? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // The claude.ai usage API returns various formats — parse what we can
        let planType = json["membershipType"] as? String
            ?? json["plan"] as? String
            ?? "pro"

        // Session (5-hour) usage
        let sessionPercent: Double
        let sessionReset: Int

        if let rateLimit = json["messageLimit"] as? [String: Any] {
            let remaining = rateLimit["remaining"] as? Double ?? 0
            let limit = rateLimit["limit"] as? Double ?? 1
            sessionPercent = limit > 0 ? (1.0 - remaining / limit) : 0
            let resetAt = rateLimit["resetsAt"] as? String
            sessionReset = secondsUntil(isoDate: resetAt)
        } else if let percent = json["sessionPercentUsed"] as? Double {
            sessionPercent = percent
            sessionReset = json["sessionResetSeconds"] as? Int ?? 0
        } else {
            sessionPercent = 0
            sessionReset = 0
        }

        // Weekly usage (if available)
        let weeklyPercent: Double
        let weeklyReset: Int

        if let daily = json["dailyLimit"] as? [String: Any] {
            let remaining = daily["remaining"] as? Double ?? 0
            let limit = daily["limit"] as? Double ?? 1
            weeklyPercent = limit > 0 ? (1.0 - remaining / limit) : 0
            let resetAt = daily["resetsAt"] as? String
            weeklyReset = secondsUntil(isoDate: resetAt)
        } else {
            weeklyPercent = 0
            weeklyReset = 0
        }

        return ClaudeUsageData(
            planType: planType,
            sessionPercentUsed: sessionPercent,
            sessionResetSeconds: sessionReset,
            weeklyPercentUsed: weeklyPercent,
            weeklyResetSeconds: weeklyReset
        )
    }

    private func secondsUntil(isoDate: String?) -> Int {
        guard let dateStr = isoDate else { return 0 }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: dateStr) else {
            // Try without fractional seconds
            formatter.formatOptions = [.withInternetDateTime]
            guard let date = formatter.date(from: dateStr) else { return 0 }
            return max(0, Int(date.timeIntervalSinceNow))
        }
        return max(0, Int(date.timeIntervalSinceNow))
    }
}
