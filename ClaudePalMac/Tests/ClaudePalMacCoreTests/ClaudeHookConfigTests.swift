import Testing
import Foundation
@testable import ClaudePalMacCore

@Suite("ClaudeHookConfig Tests")
struct ClaudeHookConfigTests {

    /// Creates a temp directory and returns a config pointing at it.
    private func makeConfig() throws -> (ClaudeHookConfig, String) {
        let tmp = NSTemporaryDirectory() + "claudepal-test-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: tmp, withIntermediateDirectories: true)
        let settingsPath = tmp + "/settings.json"
        let claudePalDir = tmp + "/claudepal"
        let config = ClaudeHookConfig(
            port: 52429,
            settingsPath: settingsPath,
            claudePalDir: claudePalDir
        )
        return (config, tmp)
    }

    private func cleanup(_ path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    // MARK: - Fresh Install

    @Test("Install creates forwarding script and hook entries from scratch")
    func freshInstall() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        try config.install()

        // Script exists and is executable
        let scriptPath = config.claudePalDir + "/hook-forward.sh"
        let attrs = try FileManager.default.attributesOfItem(atPath: scriptPath)
        let perms = attrs[.posixPermissions] as? Int
        #expect(perms == 0o755)

        // Script contains our port
        let scriptContent = try String(contentsOfFile: scriptPath, encoding: .utf8)
        #expect(scriptContent.contains("52429"))
        #expect(scriptContent.contains("curl"))

        // Settings file has all required hooks
        let data = try Data(contentsOf: URL(fileURLWithPath: config.settingsPath))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for (hookType, _) in ClaudeHookConfig.requiredHooks {
            let entries = hooks[hookType] as? [[String: Any]]
            #expect(entries != nil, "Missing hook type: \(hookType)")
            #expect(entries?.count == 1)
        }

        #expect(try config.isInstalled() == true)
    }

    // MARK: - Idempotency

    @Test("Installing twice produces the same result")
    func idempotent() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        try config.install()
        try config.install()

        let data = try Data(contentsOf: URL(fileURLWithPath: config.settingsPath))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        // Should have exactly 1 ClaudePal entry per hook type, not 2
        for (hookType, _) in ClaudeHookConfig.requiredHooks {
            let entries = hooks[hookType] as! [[String: Any]]
            let claudePalEntries = entries.filter { config.isClaudePalEntry($0) }
            #expect(claudePalEntries.count == 1, "Duplicate entries for \(hookType)")
        }
    }

    // MARK: - Preserves Existing Hooks

    @Test("Install does not clobber existing hooks from other tools")
    func preservesExistingHooks() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        // Write a pre-existing settings file with other hooks
        let existingSettings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "hooks": [
                            ["command": "/usr/local/bin/other-tool hook", "type": "command"]
                        ],
                        "matcher": ""
                    ]
                ],
                "Notification": [
                    [
                        "hooks": [
                            ["command": "~/.codync/notify.sh", "type": "command"]
                        ]
                    ]
                ]
            ],
            "permissions": ["allow": ["Bash(ls:*)"]],
            "voiceEnabled": true
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        let dir = (config.settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: config.settingsPath))

        // Install ClaudePal hooks
        try config.install()

        // Read back
        let newData = try Data(contentsOf: URL(fileURLWithPath: config.settingsPath))
        let settings = try JSONSerialization.jsonObject(with: newData) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        // PreToolUse should have 2 entries: the original + ClaudePal
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        #expect(preToolUse.count == 2)

        // Notification should have 2 entries: codync + ClaudePal
        let notification = hooks["Notification"] as! [[String: Any]]
        #expect(notification.count == 2)

        // Other settings should be preserved
        let permissions = settings["permissions"] as? [String: Any]
        #expect(permissions != nil)
        #expect(settings["voiceEnabled"] as? Bool == true)
    }

    // MARK: - Uninstall

    @Test("Uninstall removes only ClaudePal hooks, preserves others")
    func uninstall() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        // Write existing + install
        let existingSettings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    [
                        "hooks": [
                            ["command": "/usr/local/bin/other-tool hook", "type": "command"]
                        ]
                    ]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: existingSettings, options: .prettyPrinted)
        let dir = (config.settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: config.settingsPath))

        try config.install()
        try config.uninstall()

        let newData = try Data(contentsOf: URL(fileURLWithPath: config.settingsPath))
        let settings = try JSONSerialization.jsonObject(with: newData) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        // PreToolUse should still have the other tool's entry
        let preToolUse = hooks["PreToolUse"] as! [[String: Any]]
        #expect(preToolUse.count == 1)
        let cmd = ((preToolUse[0]["hooks"] as! [[String: Any]])[0]["command"] as! String)
        #expect(cmd.contains("other-tool"))

        // ClaudePal-only hook types should be gone entirely
        #expect(hooks["PostToolUse"] == nil)
        #expect(hooks["Stop"] == nil)

        // Script should be deleted
        let scriptPath = config.claudePalDir + "/hook-forward.sh"
        #expect(!FileManager.default.fileExists(atPath: scriptPath))

        #expect(try config.isInstalled() == false)
    }

    // MARK: - No Settings File

    @Test("Install works when settings.json does not exist")
    func noExistingSettingsFile() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        #expect(!FileManager.default.fileExists(atPath: config.settingsPath))

        try config.install()

        #expect(FileManager.default.fileExists(atPath: config.settingsPath))
        #expect(try config.isInstalled() == true)
    }

    // MARK: - Async Flag

    @Test("All hooks are async (notification mode)")
    func asyncFlags() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        try config.install()

        let data = try Data(contentsOf: URL(fileURLWithPath: config.settingsPath))
        let settings = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        let hooks = settings["hooks"] as! [String: Any]

        for (hookType, _) in ClaudeHookConfig.requiredHooks {
            let entries = hooks[hookType] as! [[String: Any]]
            let hook = (entries[0]["hooks"] as! [[String: Any]])[0]
            #expect(hook["async"] as? Bool == true, "Expected \(hookType) to be async")
        }
    }

    // MARK: - Detection

    @Test("isInstalled returns false when no ClaudePal hooks present")
    func notInstalled() throws {
        let (config, tmp) = try makeConfig()
        defer { cleanup(tmp) }

        #expect(try config.isInstalled() == false)

        // Write settings with only other hooks
        let settings: [String: Any] = [
            "hooks": [
                "PreToolUse": [
                    ["hooks": [["command": "other-tool", "type": "command"]]]
                ]
            ]
        ]
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        let dir = (config.settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        try data.write(to: URL(fileURLWithPath: config.settingsPath))

        #expect(try config.isInstalled() == false)
    }
}
