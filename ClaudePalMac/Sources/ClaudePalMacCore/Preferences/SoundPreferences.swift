import Foundation

// MARK: - Sound Event Types

public enum SoundEventType: String, CaseIterable, Codable, Sendable {
    case permissionPrompt
    case taskCompletion
    case notification
}

// MARK: - Sound Preferences

public struct SoundPreferences: Codable, Equatable, Sendable {
    public var isMuted: Bool
    public var sounds: [SoundEventType: String]

    public init(isMuted: Bool = false, sounds: [SoundEventType: String]? = nil) {
        self.isMuted = isMuted
        self.sounds = sounds ?? Self.defaultSounds
    }

    public static let defaultSounds: [SoundEventType: String] = [
        .permissionPrompt: "Ping",
        .taskCompletion: "Glass",
        .notification: "Pop",
    ]

    public static let `default` = SoundPreferences()

    // MARK: - UserDefaults persistence

    private static let storageKey = "claudepal.soundPreferences"

    public static func load() -> SoundPreferences {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let prefs = try? JSONDecoder().decode(SoundPreferences.self, from: data)
        else {
            return .default
        }
        return prefs
    }

    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    // MARK: - System sound discovery

    public static func availableSystemSounds() -> [String] {
        let fm = FileManager.default
        let dirs = ["/System/Library/Sounds", "/Library/Sounds"]
        var names: Set<String> = []

        for dir in dirs {
            guard let files = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for file in files {
                let name = (file as NSString).deletingPathExtension
                if !name.isEmpty {
                    names.insert(name)
                }
            }
        }

        return names.sorted()
    }

    public func soundName(for event: SoundEventType) -> String {
        sounds[event] ?? Self.defaultSounds[event] ?? "Ping"
    }
}
