import Foundation

// MARK: - Model Info

public struct ModelInfo: Equatable, Sendable {
    public let rawModel: String
    public let friendlyName: String
    public let isThinking: Bool
    public let lastUsage: TokenUsage?

    public init(rawModel: String, friendlyName: String, isThinking: Bool, lastUsage: TokenUsage?) {
        self.rawModel = rawModel
        self.friendlyName = friendlyName
        self.isThinking = isThinking
        self.lastUsage = lastUsage
    }
}

// MARK: - Token Usage

public struct TokenUsage: Equatable, Sendable {
    public let inputTokens: Int
    public let outputTokens: Int
    public let cacheReadTokens: Int

    public init(inputTokens: Int, outputTokens: Int, cacheReadTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
    }
}

// MARK: - JSONL Parser

public struct JSONLParser {

    /// Parse the last assistant message from a JSONL file to extract model info.
    /// Reads only the last `tailLines` lines for efficiency.
    public static func parseLastAssistantMessage(from url: URL, tailLines: Int = 80) -> ModelInfo? {
        guard let data = try? Data(contentsOf: url),
              let content = String(data: data, encoding: .utf8)
        else { return nil }

        // Get last N lines
        let lines = content.components(separatedBy: "\n")
        let tail = lines.suffix(tailLines)

        // Search backwards for the last assistant message with a model field
        for line in tail.reversed() {
            guard !line.isEmpty,
                  let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  json["type"] as? String == "assistant",
                  let message = json["message"] as? [String: Any],
                  let model = message["model"] as? String
            else { continue }

            let friendly = friendlyModelName(model)
            let thinking = detectThinking(message: message)
            let usage = parseUsage(message: message)

            return ModelInfo(
                rawModel: model,
                friendlyName: friendly,
                isThinking: thinking,
                lastUsage: usage
            )
        }

        return nil
    }

    /// Convert raw model ID to a friendly display name.
    /// "claude-opus-4-6" → "Opus 4.6"
    /// "claude-sonnet-4-6" → "Sonnet 4.6"
    /// "claude-haiku-4-5-20251001" → "Haiku 4.5"
    public static func friendlyModelName(_ raw: String) -> String {
        // Strip "claude-" prefix
        var name = raw
        if name.hasPrefix("claude-") {
            name = String(name.dropFirst(7))
        }

        // Known model families
        let families = ["opus", "sonnet", "haiku"]
        var family = ""
        for f in families {
            if name.hasPrefix(f) {
                family = f.prefix(1).uppercased() + f.dropFirst()
                name = String(name.dropFirst(f.count))
                break
            }
        }

        if family.isEmpty {
            return raw // Unknown model, return as-is
        }

        // Strip leading dash
        if name.hasPrefix("-") {
            name = String(name.dropFirst())
        }

        // Extract version: look for digits possibly separated by dashes
        // "4-6" → "4.6", "4-5-20251001" → "4.5", "4-20250514" → "4"
        let parts = name.split(separator: "-")
        var versionParts: [String] = []

        for part in parts {
            if part.count <= 2, part.allSatisfy({ $0.isNumber }) {
                versionParts.append(String(part))
            } else {
                break // Stop at date suffix or unknown part
            }
        }

        let version = versionParts.joined(separator: ".")

        if version.isEmpty {
            return family
        }
        return "\(family) \(version)"
    }

    // MARK: - Private

    private static func detectThinking(message: [String: Any]) -> Bool {
        guard let content = message["content"] as? [[String: Any]] else { return false }
        return content.contains { $0["type"] as? String == "thinking" }
    }

    private static func parseUsage(message: [String: Any]) -> TokenUsage? {
        guard let usage = message["usage"] as? [String: Any],
              let input = usage["input_tokens"] as? Int,
              let output = usage["output_tokens"] as? Int
        else { return nil }

        let cacheRead = usage["cache_read_input_tokens"] as? Int ?? 0
        return TokenUsage(inputTokens: input, outputTokens: output, cacheReadTokens: cacheRead)
    }
}
