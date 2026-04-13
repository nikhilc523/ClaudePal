import Foundation

/// Manages installation and removal of ClaudePal hooks in ~/.claude/settings.json.
///
/// The installer:
/// - Creates a forwarding script at ~/.claudepal/hook-forward.sh
/// - Adds hook entries to settings.json for each required hook type
/// - Is idempotent: running it twice produces the same result
/// - Never clobbers existing user hooks from other tools
public struct ClaudeHookConfig {

    /// Marker used to identify ClaudePal hook entries.
    static let hookMarker = "claudepal/hook-forward.sh"

    /// Hook types ClaudePal needs to receive.
    /// PreToolUse is synchronous (Claude waits for the response).
    /// Others are async (fire-and-forget, don't block Claude).
    static let requiredHooks: [(type: String, async: Bool)] = [
        ("PreToolUse", true),
        ("PostToolUse", true),
        ("PermissionRequest", true),
        ("Notification", true),
        ("Stop", true),
    ]

    /// Port the hook server listens on.
    public let port: Int

    /// Path to ~/.claude/settings.json (injectable for testing).
    public let settingsPath: String

    /// Path to ~/.claudepal/ directory (injectable for testing).
    public let claudePalDir: String

    public init(
        port: Int = 52429,
        settingsPath: String = NSHomeDirectory() + "/.claude/settings.json",
        claudePalDir: String = NSHomeDirectory() + "/.claudepal"
    ) {
        self.port = port
        self.settingsPath = settingsPath
        self.claudePalDir = claudePalDir
    }

    // MARK: - Install

    /// Install ClaudePal hooks. Idempotent — safe to call multiple times.
    public func install() throws {
        try writeForwardingScript()
        try addHooksToSettings()
    }

    /// Remove all ClaudePal hooks from settings.json and delete the forwarding script.
    public func uninstall() throws {
        try removeHooksFromSettings()
        let scriptPath = claudePalDir + "/hook-forward.sh"
        if FileManager.default.fileExists(atPath: scriptPath) {
            try FileManager.default.removeItem(atPath: scriptPath)
        }
    }

    /// Check if ClaudePal hooks are currently installed.
    public func isInstalled() throws -> Bool {
        guard let settings = try readSettings() else { return false }
        guard let hooks = settings["hooks"] as? [String: Any] else { return false }

        // Check if at least one of our hook types has a ClaudePal entry
        for (hookType, _) in Self.requiredHooks {
            if let entries = hooks[hookType] as? [[String: Any]] {
                if entries.contains(where: { isClaudePalEntry($0) }) {
                    return true
                }
            }
        }
        return false
    }

    // MARK: - Forwarding Script

    /// The shell script content that forwards hook payloads to our HTTP server.
    func forwardingScriptContent() -> String {
        """
        #!/bin/bash
        # ClaudePal hook forwarder — do not edit, managed by ClaudePal.app
        # Forwards Claude Code hook payloads to the ClaudePal local server.
        # $1 = hook type (PreToolUse, PostToolUse, Notification, Stop)
        exec curl -sf --max-time 120 -X POST "http://127.0.0.1:\(port)/hook/$1" \\
            -H 'Content-Type: application/json' -d @- 2>/dev/null || true
        """
    }

    func writeForwardingScript() throws {
        let fm = FileManager.default
        if !fm.fileExists(atPath: claudePalDir) {
            try fm.createDirectory(atPath: claudePalDir, withIntermediateDirectories: true)
        }

        let scriptPath = claudePalDir + "/hook-forward.sh"
        let content = forwardingScriptContent()
        try content.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        // Make executable
        try fm.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: scriptPath
        )
    }

    // MARK: - Settings JSON

    func readSettings() throws -> [String: Any]? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: settingsPath) else { return nil }
        let data = try Data(contentsOf: URL(fileURLWithPath: settingsPath))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json
    }

    func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        )
        let dir = (settingsPath as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        try data.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }

    func addHooksToSettings() throws {
        var settings = try readSettings() ?? [:]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]

        let scriptPath = claudePalDir + "/hook-forward.sh"

        for (hookType, isAsync) in Self.requiredHooks {
            var entries = hooks[hookType] as? [[String: Any]] ?? []

            // Remove any existing ClaudePal entries (for idempotent update)
            entries.removeAll { isClaudePalEntry($0) }

            // Build the new ClaudePal hook entry
            var hookDef: [String: Any] = [
                "command": "\(scriptPath) \(hookType)",
                "type": "command",
            ]
            if isAsync {
                hookDef["async"] = true
            }

            let entry: [String: Any] = [
                "hooks": [hookDef]
            ]

            entries.append(entry)
            hooks[hookType] = entries
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    func removeHooksFromSettings() throws {
        guard var settings = try readSettings() else { return }
        guard var hooks = settings["hooks"] as? [String: Any] else { return }

        for (hookType, _) in Self.requiredHooks {
            guard var entries = hooks[hookType] as? [[String: Any]] else { continue }
            entries.removeAll { isClaudePalEntry($0) }
            if entries.isEmpty {
                hooks.removeValue(forKey: hookType)
            } else {
                hooks[hookType] = entries
            }
        }

        settings["hooks"] = hooks
        try writeSettings(settings)
    }

    // MARK: - Detection

    /// Check if a hook entry belongs to ClaudePal.
    func isClaudePalEntry(_ entry: [String: Any]) -> Bool {
        guard let hooksList = entry["hooks"] as? [[String: Any]] else { return false }
        return hooksList.contains { hook in
            guard let command = hook["command"] as? String else { return false }
            return command.contains(Self.hookMarker)
        }
    }
}
