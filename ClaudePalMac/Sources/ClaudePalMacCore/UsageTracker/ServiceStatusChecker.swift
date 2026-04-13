import Foundation

// MARK: - Claude Service Status

public struct ClaudeServiceStatus: Equatable, Sendable {
    public let indicator: String
    public let description: String

    public init(indicator: String, description: String) {
        self.indicator = indicator
        self.description = description
    }

    public var isOperational: Bool { indicator == "none" }
    public var isDegraded: Bool { indicator == "minor" || indicator == "major" }
    public var isCritical: Bool { indicator == "critical" }
}

// MARK: - Service Status Checker

public actor ServiceStatusChecker {

    private let statusURL = URL(string: "https://status.claude.com/api/v2/status.json")!
    private var pollTimer: Timer?
    private var callback: (@Sendable (ClaudeServiceStatus?) -> Void)?

    public init() {}

    /// Fetch current status once.
    public func fetchStatus() async -> ClaudeServiceStatus? {
        do {
            let (data, _) = try await URLSession.shared.data(from: statusURL)
            return parse(data: data)
        } catch {
            return nil
        }
    }

    /// Start polling at the given interval.
    public func startPolling(
        interval: TimeInterval = 60,
        callback: @escaping @Sendable (ClaudeServiceStatus?) -> Void
    ) {
        self.callback = callback

        // Fetch immediately
        Task {
            let status = await fetchStatus()
            callback(status)
        }

        // Schedule recurring fetches
        Task { @MainActor in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                Task {
                    let status = await self.fetchStatus()
                    await self.notifyCallback(status: status)
                }
            }
            await self.setTimer(timer)
        }
    }

    public func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
        callback = nil
    }

    // MARK: - Private

    private func setTimer(_ timer: Timer) {
        self.pollTimer = timer
    }

    private func notifyCallback(status: ClaudeServiceStatus?) {
        callback?(status)
    }

    private func parse(data: Data) -> ClaudeServiceStatus? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let status = json["status"] as? [String: Any],
              let indicator = status["indicator"] as? String,
              let description = status["description"] as? String
        else { return nil }

        return ClaudeServiceStatus(indicator: indicator, description: description)
    }
}
