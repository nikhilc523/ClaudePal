import XCTest
@testable import ClaudePalMacCore

final class SoundPreferencesTests: XCTestCase {

    func testDefaultPreferences() {
        let prefs = SoundPreferences.default
        XCTAssertFalse(prefs.isMuted)
        XCTAssertEqual(prefs.soundName(for: .permissionPrompt), "Ping")
        XCTAssertEqual(prefs.soundName(for: .taskCompletion), "Glass")
        XCTAssertEqual(prefs.soundName(for: .notification), "Pop")
    }

    func testCodableRoundTrip() throws {
        var prefs = SoundPreferences()
        prefs.isMuted = true
        prefs.sounds[.permissionPrompt] = "Hero"
        prefs.sounds[.taskCompletion] = "Submarine"

        let data = try JSONEncoder().encode(prefs)
        let decoded = try JSONDecoder().decode(SoundPreferences.self, from: data)

        XCTAssertEqual(prefs, decoded)
        XCTAssertTrue(decoded.isMuted)
        XCTAssertEqual(decoded.soundName(for: .permissionPrompt), "Hero")
        XCTAssertEqual(decoded.soundName(for: .taskCompletion), "Submarine")
    }

    func testAvailableSystemSoundsNotEmpty() {
        let sounds = SoundPreferences.availableSystemSounds()
        XCTAssertFalse(sounds.isEmpty, "Should find at least one system sound")
        // macOS always has these
        XCTAssertTrue(sounds.contains("Ping") || sounds.contains("Blow") || sounds.contains("Glass"),
                      "Should contain common macOS sounds")
    }

    func testAvailableSystemSoundsAreSorted() {
        let sounds = SoundPreferences.availableSystemSounds()
        XCTAssertEqual(sounds, sounds.sorted())
    }

    func testSoundNameFallsBackToDefault() {
        let prefs = SoundPreferences(isMuted: false, sounds: [:])
        XCTAssertEqual(prefs.soundName(for: .permissionPrompt), "Ping")
    }
}
