import Foundation

// MARK: - Session Tokens

public struct SessionTokens: Equatable, Sendable {
    public var totalInputTokens: Int
    public var totalOutputTokens: Int
    public var totalCacheReadTokens: Int
    public var messageCount: Int

    public init(
        totalInputTokens: Int = 0,
        totalOutputTokens: Int = 0,
        totalCacheReadTokens: Int = 0,
        messageCount: Int = 0
    ) {
        self.totalInputTokens = totalInputTokens
        self.totalOutputTokens = totalOutputTokens
        self.totalCacheReadTokens = totalCacheReadTokens
        self.messageCount = messageCount
    }

    public static let zero = SessionTokens()
}

// MARK: - Local Token Tracker

public final class LocalTokenTracker: @unchecked Sendable {

    private let lock = NSLock()
    private var _tokens = SessionTokens.zero
    private var _lastSessionId: String?

    public init() {}

    public var current: SessionTokens {
        lock.lock()
        defer { lock.unlock() }
        return _tokens
    }

    /// Accumulate usage from a parsed assistant message.
    public func accumulate(usage: TokenUsage, sessionId: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        // Reset if session changed
        if let sid = sessionId, sid != _lastSessionId {
            _tokens = .zero
            _lastSessionId = sid
        }

        _tokens.totalInputTokens += usage.inputTokens
        _tokens.totalOutputTokens += usage.outputTokens
        _tokens.totalCacheReadTokens += usage.cacheReadTokens
        _tokens.messageCount += 1
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        _tokens = .zero
        _lastSessionId = nil
    }

    // MARK: - Formatting

    public static func formatTokenCount(_ count: Int) -> String {
        if count < 1000 { return "\(count)" }
        if count < 10_000 { return String(format: "%.1fK", Double(count) / 1000) }
        if count < 1_000_000 { return String(format: "%.0fK", Double(count) / 1000) }
        return String(format: "%.1fM", Double(count) / 1_000_000)
    }
}
