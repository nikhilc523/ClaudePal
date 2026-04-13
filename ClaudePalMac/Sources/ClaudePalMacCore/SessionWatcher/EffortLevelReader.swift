import Foundation

public enum EffortLevel: String, Sendable {
    case low
    case medium
    case high

    public var displayName: String {
        rawValue.capitalized
    }

    public var emoji: String {
        switch self {
        case .low: "🔋"
        case .medium: "⚡"
        case .high: "🔥"
        }
    }
}

public struct EffortLevelReader {

    public static func read(
        settingsPath: String = NSHomeDirectory() + "/.claude/settings.json"
    ) -> EffortLevel {
        guard FileManager.default.fileExists(atPath: settingsPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let level = json["effortLevel"] as? String
        else {
            return .high
        }
        return EffortLevel(rawValue: level) ?? .high
    }
}
