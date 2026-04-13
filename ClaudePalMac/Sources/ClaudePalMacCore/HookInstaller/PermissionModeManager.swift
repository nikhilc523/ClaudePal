import Foundation

// MARK: - Permission Mode

public enum PermissionMode: String, CaseIterable, Sendable {
    case normal
    case permissive
    case restrictive

    public var displayName: String {
        switch self {
        case .normal: "Normal"
        case .permissive: "Permissive"
        case .restrictive: "Restrictive"
        }
    }
}

// MARK: - Permission Mode Manager

public struct PermissionModeManager: Sendable {

    private static let backupKey = "claudepal.savedPermissions"

    /// Broad allow rules for permissive mode.
    private static let permissiveRules: [String] = [
        "Bash(*)", "Write(*)", "Edit(*)", "Read(*)",
        "Glob(*)", "Grep(*)", "WebFetch(*)", "WebSearch(*)",
        "NotebookEdit(*)", "Agent(*)",
    ]

    private let settingsPath: String

    public init(settingsPath: String = NSHomeDirectory() + "/.claude/settings.json") {
        self.settingsPath = settingsPath
    }

    // MARK: - Detection

    public func detectCurrentMode() -> PermissionMode {
        guard let settings = readSettings(),
              let permissions = settings["permissions"] as? [String: Any],
              let allow = permissions["allow"] as? [String]
        else {
            return .normal
        }

        if allow.isEmpty {
            return .restrictive
        }

        // Need at least 3 broad wildcards to be considered permissive
        let broadCount = allow.filter { Self.permissiveRules.contains($0) }.count
        if broadCount >= 3 {
            return .permissive
        }

        return .normal
    }

    // MARK: - Apply

    public func apply(mode: PermissionMode) throws {
        switch mode {
        case .normal:
            try restoreNormal()
        case .permissive:
            try applyPermissive()
        case .restrictive:
            try applyRestrictive()
        }
    }

    private func applyPermissive() throws {
        saveCurrentAsBackup()
        var settings = readSettings() ?? [:]
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        var allow = permissions["allow"] as? [String] ?? []

        // Add permissive rules without duplicating
        for rule in Self.permissiveRules {
            if !allow.contains(rule) {
                allow.append(rule)
            }
        }

        permissions["allow"] = allow
        settings["permissions"] = permissions
        try writeSettings(settings)
    }

    private func applyRestrictive() throws {
        saveCurrentAsBackup()
        var settings = readSettings() ?? [:]
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        permissions["allow"] = [String]()
        settings["permissions"] = permissions
        try writeSettings(settings)
    }

    private func restoreNormal() throws {
        guard let backed = UserDefaults.standard.stringArray(forKey: Self.backupKey) else {
            // No backup — just remove broad wildcards
            var settings = readSettings() ?? [:]
            var permissions = settings["permissions"] as? [String: Any] ?? [:]
            var allow = permissions["allow"] as? [String] ?? []
            allow.removeAll { Self.permissiveRules.contains($0) }
            permissions["allow"] = allow
            settings["permissions"] = permissions
            try writeSettings(settings)
            return
        }

        var settings = readSettings() ?? [:]
        var permissions = settings["permissions"] as? [String: Any] ?? [:]
        permissions["allow"] = backed
        settings["permissions"] = permissions
        try writeSettings(settings)
        UserDefaults.standard.removeObject(forKey: Self.backupKey)
    }

    // MARK: - Backup

    private func saveCurrentAsBackup() {
        guard let settings = readSettings(),
              let permissions = settings["permissions"] as? [String: Any],
              let allow = permissions["allow"] as? [String]
        else { return }

        // Only save if not already backed up (don't overwrite original with permissive state)
        if UserDefaults.standard.stringArray(forKey: Self.backupKey) == nil {
            UserDefaults.standard.set(allow, forKey: Self.backupKey)
        }
    }

    // MARK: - Settings I/O (mirrors ClaudeHookConfig)

    private func readSettings() -> [String: Any]? {
        guard FileManager.default.fileExists(atPath: settingsPath),
              let data = try? Data(contentsOf: URL(fileURLWithPath: settingsPath)),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return json
    }

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }
}
