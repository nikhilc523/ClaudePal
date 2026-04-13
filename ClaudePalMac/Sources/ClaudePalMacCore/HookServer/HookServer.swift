import Foundation
import Hummingbird

/// Lightweight localhost HTTP server that receives Claude Code hook payloads.
public actor HookServer {
    private let processor: HookProcessor
    private let port: Int
    private var app: (any ApplicationProtocol)?
    private var serverTask: Task<Void, any Error>?

    public init(processor: HookProcessor, port: Int = 52429) {
        self.processor = processor
        self.port = port
    }

    /// Start the HTTP server.
    public func start() async throws {
        let processor = self.processor
        let router = Router()

        // Health check
        router.get("/health") { _, _ in
            let waitCount = await processor.activeWaitCount
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: """
                    {"status":"ok","pending_decisions":\(waitCount)}
                    """))
            )
        }

        // Main hook endpoint — Claude Code posts here
        router.post("/hook") { request, context in
            let body = try await request.body.collect(upTo: 1_048_576) // 1MB max
            let payload = try JSONDecoder().decode(HookPayload.self, from: body)

            let response = try await processor.process(payload)

            if let response {
                let data = try JSONEncoder().encode(response)
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: .init(data: data))
                )
            } else {
                return Response(
                    status: .ok,
                    headers: [.contentType: "application/json"],
                    body: .init(byteBuffer: .init(string: "{}"))
                )
            }
        }

        // Raw Claude Code hook endpoint — forwarding script sends here
        // Path: /hook/{hookType} where hookType is PreToolUse, PostToolUse, etc.
        router.post("/hook/{hookType}") { request, context in
            let body = try await request.body.collect(upTo: 1_048_576)
            let raw = try JSONDecoder().decode(RawHookPayload.self, from: body)
            let payload = raw.toHookPayload()

            let response = try await processor.process(payload)
            let rawResponse = RawHookResponse.from(response)

            let data = try JSONEncoder().encode(rawResponse)
            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(data: data))
            )
        }

        // Resolve a decision from local UI or future CloudKit relay
        router.post("/decisions/{id}/resolve") { request, context in
            guard let decisionId = context.parameters.get("id") else {
                return Response(status: .badRequest)
            }

            let body = try await request.body.collect(upTo: 65_536)
            let resolution = try JSONDecoder().decode(DecisionResolution.self, from: body)

            try await processor.resolve(
                decisionId: decisionId,
                approved: resolution.approved,
                reason: resolution.reason
            )

            return Response(
                status: .ok,
                headers: [.contentType: "application/json"],
                body: .init(byteBuffer: .init(string: #"{"resolved":true}"#))
            )
        }

        let app = Application(router: router, configuration: .init(address: .hostname("127.0.0.1", port: port)))

        serverTask = Task {
            try await app.run()
        }
    }

    /// Stop the server.
    public func stop() {
        serverTask?.cancel()
        serverTask = nil
    }
}

/// Request body for resolving a decision via the REST API.
public struct DecisionResolution: Codable, Sendable {
    public let approved: Bool
    public let reason: String?

    public init(approved: Bool, reason: String? = nil) {
        self.approved = approved
        self.reason = reason
    }
}
