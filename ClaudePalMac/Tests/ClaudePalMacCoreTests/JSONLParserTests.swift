import XCTest
@testable import ClaudePalMacCore

final class JSONLParserTests: XCTestCase {

    // MARK: - Friendly Model Name

    func testFriendlyNameOpus46() {
        XCTAssertEqual(JSONLParser.friendlyModelName("claude-opus-4-6"), "Opus 4.6")
    }

    func testFriendlyNameSonnet46() {
        XCTAssertEqual(JSONLParser.friendlyModelName("claude-sonnet-4-6"), "Sonnet 4.6")
    }

    func testFriendlyNameHaikuWithDate() {
        XCTAssertEqual(JSONLParser.friendlyModelName("claude-haiku-4-5-20251001"), "Haiku 4.5")
    }

    func testFriendlyNameSonnetWithDate() {
        XCTAssertEqual(JSONLParser.friendlyModelName("claude-sonnet-4-20250514"), "Sonnet 4")
    }

    func testFriendlyNameUnknownModel() {
        XCTAssertEqual(JSONLParser.friendlyModelName("some-other-model"), "some-other-model")
    }

    // MARK: - JSONL Parsing

    func testParseAssistantMessageWithModel() throws {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"hi"}],"usage":{"input_tokens":100,"output_tokens":50,"cache_read_input_tokens":20}}}
        """

        let url = try writeTempFile(content: jsonl)
        let result = JSONLParser.parseLastAssistantMessage(from: url)

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.rawModel, "claude-opus-4-6")
        XCTAssertEqual(result?.friendlyName, "Opus 4.6")
        XCTAssertFalse(result?.isThinking ?? true)
        XCTAssertEqual(result?.lastUsage?.inputTokens, 100)
        XCTAssertEqual(result?.lastUsage?.outputTokens, 50)
        XCTAssertEqual(result?.lastUsage?.cacheReadTokens, 20)
    }

    func testDetectsThinkingMode() throws {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-sonnet-4-6","id":"msg_2","type":"message","role":"assistant","content":[{"type":"thinking","thinking":"","signature":"abc"},{"type":"text","text":"done"}],"usage":{"input_tokens":10,"output_tokens":5}}}
        """

        let url = try writeTempFile(content: jsonl)
        let result = JSONLParser.parseLastAssistantMessage(from: url)

        XCTAssertNotNil(result)
        XCTAssertTrue(result?.isThinking ?? false)
    }

    func testReturnsNilForEmptyFile() throws {
        let url = try writeTempFile(content: "")
        let result = JSONLParser.parseLastAssistantMessage(from: url)
        XCTAssertNil(result)
    }

    func testReturnsNilForNoAssistantMessages() throws {
        let jsonl = """
        {"type":"user","message":{"role":"user","content":"hello"}}
        {"type":"system","subtype":"turn_duration","durationMs":500}
        """

        let url = try writeTempFile(content: jsonl)
        let result = JSONLParser.parseLastAssistantMessage(from: url)
        XCTAssertNil(result)
    }

    func testPicksLastAssistantMessage() throws {
        let jsonl = """
        {"type":"assistant","message":{"model":"claude-haiku-4-5-20251001","id":"msg_1","type":"message","role":"assistant","content":[{"type":"text","text":"first"}],"usage":{"input_tokens":10,"output_tokens":5}}}
        {"type":"user","message":{"role":"user","content":"again"}}
        {"type":"assistant","message":{"model":"claude-opus-4-6","id":"msg_2","type":"message","role":"assistant","content":[{"type":"text","text":"second"}],"usage":{"input_tokens":20,"output_tokens":10}}}
        """

        let url = try writeTempFile(content: jsonl)
        let result = JSONLParser.parseLastAssistantMessage(from: url)

        XCTAssertEqual(result?.rawModel, "claude-opus-4-6")
        XCTAssertEqual(result?.friendlyName, "Opus 4.6")
    }

    // MARK: - Helpers

    private func writeTempFile(content: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".jsonl")
        try content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
