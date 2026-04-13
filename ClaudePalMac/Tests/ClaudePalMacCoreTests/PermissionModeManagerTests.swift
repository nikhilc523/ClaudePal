import XCTest
@testable import ClaudePalMacCore

final class PermissionModeManagerTests: XCTestCase {

    private var tempSettingsPath: String!
    private var manager: PermissionModeManager!

    override func setUp() {
        super.setUp()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        tempSettingsPath = tempDir.appendingPathComponent("settings.json").path
        manager = PermissionModeManager(settingsPath: tempSettingsPath)
    }

    override func tearDown() {
        let dir = (tempSettingsPath as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
        // Clean up UserDefaults backup
        UserDefaults.standard.removeObject(forKey: "claudepal.savedPermissions")
        super.tearDown()
    }

    // MARK: - Detection

    func testDetectsNormalWhenNoFile() {
        XCTAssertEqual(manager.detectCurrentMode(), .normal)
    }

    func testDetectsNormalWithCustomRules() throws {
        let settings: [String: Any] = [
            "permissions": ["allow": ["Bash(curl:*)", "Bash(git add -A)"]]
        ]
        try writeSettings(settings)
        XCTAssertEqual(manager.detectCurrentMode(), .normal)
    }

    func testDetectsRestrictiveWithEmptyAllow() throws {
        let settings: [String: Any] = [
            "permissions": ["allow": [String]()]
        ]
        try writeSettings(settings)
        XCTAssertEqual(manager.detectCurrentMode(), .restrictive)
    }

    func testDetectsPermissiveWithBroadWildcards() throws {
        let settings: [String: Any] = [
            "permissions": ["allow": ["Bash(*)", "Write(*)", "Edit(*)", "Read(*)"]]
        ]
        try writeSettings(settings)
        XCTAssertEqual(manager.detectCurrentMode(), .permissive)
    }

    // MARK: - Apply

    func testApplyPermissiveAddsBroadRules() throws {
        let settings: [String: Any] = [
            "permissions": ["allow": ["Bash(curl:*)"]]
        ]
        try writeSettings(settings)

        try manager.apply(mode: .permissive)

        let result = try readAllow()
        XCTAssertTrue(result.contains("Bash(*)"))
        XCTAssertTrue(result.contains("Write(*)"))
        XCTAssertTrue(result.contains("Bash(curl:*)")) // preserves existing
    }

    func testApplyRestrictiveClearsAllow() throws {
        let settings: [String: Any] = [
            "permissions": ["allow": ["Bash(curl:*)", "Write(*)"]]
        ]
        try writeSettings(settings)

        try manager.apply(mode: .restrictive)

        let result = try readAllow()
        XCTAssertTrue(result.isEmpty)
    }

    func testApplyNormalRestoresBackup() throws {
        let settings: [String: Any] = [
            "permissions": ["allow": ["Bash(curl:*)"]]
        ]
        try writeSettings(settings)

        // Switch to permissive (saves backup)
        try manager.apply(mode: .permissive)
        XCTAssertEqual(manager.detectCurrentMode(), .permissive)

        // Switch back to normal (restores backup)
        try manager.apply(mode: .normal)
        let result = try readAllow()
        XCTAssertEqual(result, ["Bash(curl:*)"])
    }

    // MARK: - Helpers

    private func writeSettings(_ settings: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: settings, options: .prettyPrinted)
        try data.write(to: URL(fileURLWithPath: tempSettingsPath))
    }

    private func readAllow() throws -> [String] {
        let data = try Data(contentsOf: URL(fileURLWithPath: tempSettingsPath))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        let permissions = json["permissions"] as? [String: Any] ?? [:]
        return permissions["allow"] as? [String] ?? []
    }
}
