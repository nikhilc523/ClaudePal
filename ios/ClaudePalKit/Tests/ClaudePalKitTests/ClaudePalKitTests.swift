import ClaudePalKit
import Foundation
import UserNotifications
import XCTest

final class ClaudePalKitTests: XCTestCase {
    func testPairingPayloadParsesCustomURL() throws {
        let payload = try PairingPayload(
            qrPayload: "claudepal://pair?bridgeUrl=http://127.0.0.1:19876&pairingCode=ABC123"
        )

        XCTAssertEqual(payload.bridgeURL.absoluteString, "http://127.0.0.1:19876")
        XCTAssertEqual(payload.pairingCode, "ABC123")
    }

    @MainActor
    func testPairingCoordinatorStoresConnectionAfterPairing() async throws {
        let client = FakeBridgeClient()
        let store = InMemoryConnectionStore()
        let queue = DecisionQueue(store: InMemoryDecisionQueueStore())
        let coordinator = PairingCoordinator(
            bridgeClient: client,
            connectionStore: store,
            decisionQueue: queue
        )
        let connection = try await coordinator.pair(
            using: PairingPayload(
                bridgeURL: URL(string: "http://127.0.0.1:19876")!,
                pairingCode: "PAIR01"
            ),
            deviceInfo: BridgeDeviceInfo(deviceName: "Nikhil's iPhone", platform: "iOS", appVersion: "0.1.0")
        )

        XCTAssertEqual(connection.bridgeURL.absoluteString, "http://127.0.0.1:19876")
        XCTAssertEqual(try store.load(), connection)
        XCTAssertEqual(client.completedPairings.count, 1)
    }

    func testDecisionQueuePersistsAndDrains() async throws {
        let store = InMemoryDecisionQueueStore()
        let queue = DecisionQueue(store: store)
        let client = FakeBridgeClient()
        let connection = BridgeConnection(
            bridgeURL: URL(string: "http://127.0.0.1:19876")!,
            authToken: "auth-token",
            deviceID: "device-1"
        )

        try await queue.enqueue(QueuedDecision(decisionID: "decision-1", decision: .approve))
        let initialCount = try await queue.count()
        XCTAssertEqual(initialCount, 1)

        let drained = try await queue.drain(using: client, connection: connection)
        XCTAssertEqual(drained, 1)
        let finalCount = try await queue.count()
        XCTAssertEqual(finalCount, 0)
        XCTAssertEqual(client.submittedDecisions.first?.decisionID, "decision-1")
    }

    @MainActor
    func testNotificationActionHandlerSubmitsApproveDecision() async throws {
        let client = FakeBridgeClient()
        let store = InMemoryConnectionStore(
            connection: BridgeConnection(
                bridgeURL: URL(string: "http://127.0.0.1:19876")!,
                authToken: "auth-token",
                deviceID: "device-1"
            )
        )
        let queue = DecisionQueue(store: InMemoryDecisionQueueStore())
        let authenticator = FakeLocalAuthenticator()
        let handler = NotificationActionHandler(
            bridgeClient: client,
            connectionStore: store,
            decisionQueue: queue,
            localAuthenticator: authenticator
        )

        let result = try await handler.handle(
            actionIdentifier: NotificationCategoryFactory.approveAction,
            userInfo: [
                "decisionId": "decision-1",
                "requiresAuthentication": false
            ]
        )

        XCTAssertEqual(result, .submitted)
        XCTAssertEqual(client.submittedDecisions.count, 1)
        let queueCount = try await queue.count()
        XCTAssertEqual(queueCount, 0)
        XCTAssertFalse(authenticator.didAuthenticate)
    }

    @MainActor
    func testNotificationActionHandlerQueuesOnBridgeFailure() async throws {
        let client = FakeBridgeClient()
        client.submitError = ClaudePalKitError.bridgeRequestFailed(statusCode: 500)
        let store = InMemoryConnectionStore(
            connection: BridgeConnection(
                bridgeURL: URL(string: "http://127.0.0.1:19876")!,
                authToken: "auth-token",
                deviceID: "device-1"
            )
        )
        let queueStore = InMemoryDecisionQueueStore()
        let queue = DecisionQueue(store: queueStore)
        let handler = NotificationActionHandler(
            bridgeClient: client,
            connectionStore: store,
            decisionQueue: queue,
            localAuthenticator: FakeLocalAuthenticator()
        )

        let result = try await handler.handle(
            actionIdentifier: NotificationCategoryFactory.denyAction,
            userInfo: [
                "decisionId": "decision-2",
                "requiresAuthentication": false
            ]
        )

        XCTAssertEqual(result, .queued)
        let queueCount = try await queue.count()
        XCTAssertEqual(queueCount, 1)
    }

    @MainActor
    func testNotificationActionHandlerRequiresAuthenticationForDestructiveApprovals() async throws {
        let client = FakeBridgeClient()
        let store = InMemoryConnectionStore(
            connection: BridgeConnection(
                bridgeURL: URL(string: "http://127.0.0.1:19876")!,
                authToken: "auth-token",
                deviceID: "device-1"
            )
        )
        let authenticator = FakeLocalAuthenticator()
        let handler = NotificationActionHandler(
            bridgeClient: client,
            connectionStore: store,
            decisionQueue: DecisionQueue(store: InMemoryDecisionQueueStore()),
            localAuthenticator: authenticator
        )

        let result = try await handler.handle(
            actionIdentifier: NotificationCategoryFactory.approveAction,
            userInfo: [
                "decisionId": "decision-3",
                "requiresAuthentication": true
            ]
        )

        XCTAssertEqual(result, .submitted)
        XCTAssertTrue(authenticator.didAuthenticate)
    }

    @MainActor
    func testPushRegistrationCoordinatorFormatsTokenAndUploadsRegistration() async throws {
        let client = FakeBridgeClient()
        let coordinator = PushRegistrationCoordinator(
            authorizationCenter: FakeNotificationAuthorizationCenter(granted: true),
            remoteRegistrar: FakeRemoteNotificationRegistrar(),
            bridgeClient: client
        )
        let connection = BridgeConnection(
            bridgeURL: URL(string: "http://127.0.0.1:19876")!,
            authToken: "auth-token",
            deviceID: "device-1"
        )

        try await coordinator.uploadDeviceToken(
            Data([0xDE, 0xAD, 0xBE, 0xEF]),
            connection: connection,
            deviceInfo: BridgeDeviceInfo(deviceName: "Nikhil's iPhone", platform: "iOS")
        )

        XCTAssertEqual(client.registeredDeviceTokens, ["deadbeef"])
    }

    func testNotificationCategoryFactoryDefinesActionableCategories() {
        let categories = NotificationCategoryFactory.categories()

        XCTAssertEqual(categories.count, 3)
        XCTAssertNotNil(categories.first(where: { $0.identifier == NotificationCategoryFactory.permissionRequest }))
        XCTAssertNotNil(categories.first(where: { $0.identifier == NotificationCategoryFactory.inputNeeded }))
        XCTAssertNotNil(categories.first(where: { $0.identifier == NotificationCategoryFactory.taskComplete }))
    }

    func testPendingDecisionDetectsDestructiveAuthenticationRequirement() {
        let payload = JSONValue.object([
            "tool_name": .string("Bash"),
            "tool_input": .object([
                "command": .string("rm -rf node_modules")
            ])
        ])
        let decision = BridgePendingDecisionRecord(
            id: "decision-1",
            sessionId: "session-1",
            eventId: "event-1",
            decisionType: "approve",
            status: "pending",
            payload: payload,
            createdAt: .now,
            expiresAt: nil,
            resolvedAt: nil,
            resolution: nil
        )

        XCTAssertTrue(decision.requiresAuthentication)
    }

    func testSimpleElicitationDetectorRecognizesSingleFieldForms() {
        let payload = JSONValue.object([
            "mode": .string("form"),
            "message": .string("GitHub MCP needs the repository owner."),
            "requested_schema": .object([
                "type": .string("object"),
                "properties": .object([
                    "owner": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([
                    .string("owner")
                ])
            ])
        ])

        let prompt = SimpleElicitationDetector.detectPrompt(in: payload)

        XCTAssertEqual(
            prompt,
            WatchSimpleInputPrompt(
                fieldKey: "owner",
                fieldLabel: "Owner",
                message: "GitHub MCP needs the repository owner."
            )
        )
    }

    func testSimpleElicitationDetectorRejectsComplexForms() {
        let payload = JSONValue.object([
            "mode": .string("form"),
            "requested_schema": .object([
                "type": .string("object"),
                "properties": .object([
                    "owner": .object([
                        "type": .string("string")
                    ]),
                    "repo": .object([
                        "type": .string("string")
                    ])
                ]),
                "required": .array([
                    .string("owner"),
                    .string("repo")
                ])
            ])
        ])

        XCTAssertNil(SimpleElicitationDetector.detectPrompt(in: payload))
    }

    func testBridgeDecisionSubmitInputCarriesStructuredContent() {
        let decision = BridgeDecision.submitInput(
            .object([
                "owner": .string("openai")
            ])
        )

        XCTAssertEqual(decision.decision, "submit_input")
        XCTAssertEqual(
            decision.content,
            .object([
                "owner": .string("openai")
            ])
        )
    }

    func testBridgeSnapshotAppliesRealtimeUpdates() {
        let timestamp = Date(timeIntervalSince1970: 1_000)
        let session = BridgeSessionRecord(
            id: "session-1",
            cwd: "/tmp/project",
            displayName: "project",
            status: "waiting",
            lastEventType: "PermissionRequest",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        let event = BridgeEventRecord(
            id: "event-1",
            sessionId: "session-1",
            hookEventName: "PermissionRequest",
            type: "permission_requested",
            title: "Permission Request",
            message: "rm -rf node_modules",
            payload: .object([
                "tool_name": .string("Bash")
            ]),
            createdAt: timestamp
        )
        let decision = BridgePendingDecisionRecord(
            id: "decision-1",
            sessionId: "session-1",
            eventId: "event-1",
            decisionType: "approve",
            status: "pending",
            payload: nil,
            createdAt: timestamp,
            expiresAt: nil,
            resolvedAt: nil,
            resolution: nil
        )
        let initialSnapshot = BridgeSnapshot(
            summary: BridgeSummary(
                sessionsCount: 1,
                eventsCount: 1,
                pendingDecisionsCount: 1,
                unresolvedDecisionsCount: 1,
                devicesCount: 1
            ),
            sessions: [session],
            pendingDecisions: [decision],
            recentEvents: []
        )

        let eventMessage = BridgeRealtimeMessage(
            type: "event.created",
            summary: BridgeSummary(
                sessionsCount: 1,
                eventsCount: 2,
                pendingDecisionsCount: 1,
                unresolvedDecisionsCount: 1,
                devicesCount: 1
            ),
            session: session,
            event: event,
            pendingDecision: decision
        )
        let resolvedDecision = BridgePendingDecisionRecord(
            id: "decision-1",
            sessionId: "session-1",
            eventId: "event-1",
            decisionType: "approve",
            status: "approved",
            payload: nil,
            createdAt: timestamp,
            expiresAt: nil,
            resolvedAt: timestamp,
            resolution: .object([
                "decision": .string("approve")
            ])
        )
        let resolutionMessage = BridgeRealtimeMessage(
            type: "decision.resolved",
            summary: BridgeSummary(
                sessionsCount: 1,
                eventsCount: 2,
                pendingDecisionsCount: 1,
                unresolvedDecisionsCount: 0,
                devicesCount: 1
            ),
            session: BridgeSessionRecord(
                id: "session-1",
                cwd: "/tmp/project",
                displayName: "project",
                status: "active",
                lastEventType: "PermissionRequest",
                createdAt: timestamp,
                updatedAt: timestamp
            ),
            pendingDecision: resolvedDecision
        )

        let afterEvent = initialSnapshot.applying(eventMessage)
        XCTAssertEqual(afterEvent.recentEvents.first?.id, "event-1")
        XCTAssertEqual(afterEvent.activePendingDecisions.count, 1)

        let afterResolution = afterEvent.applying(resolutionMessage)
        XCTAssertEqual(afterResolution.activePendingDecisions.count, 0)
        XCTAssertEqual(afterResolution.pendingDecisions.first?.status, "approved")
        XCTAssertEqual(afterResolution.primarySession?.status, "active")
    }
}

private final class FakeBridgeClient: BridgeClientProtocol, @unchecked Sendable {
    struct SubmittedDecision {
        let connection: BridgeConnection
        let decisionID: String
        let decision: BridgeDecision
    }

    var completedPairings: [(URL, String)] = []
    var submittedDecisions: [SubmittedDecision] = []
    var registeredDeviceTokens: [String] = []
    var submitError: Error?

    func completePairing(
        on bridgeURL: URL,
        pairingCode: String,
        deviceInfo: BridgeDeviceInfo
    ) async throws -> BridgeConnection {
        completedPairings.append((bridgeURL, pairingCode))
        return BridgeConnection(
            bridgeURL: bridgeURL,
            authToken: "paired-token",
            deviceID: "device-1"
        )
    }

    func registerDevice(
        connection: BridgeConnection,
        pushToken: String,
        notificationsEnabled: Bool,
        deviceInfo: BridgeDeviceInfo
    ) async throws {
        registeredDeviceTokens.append(pushToken)
    }

    func fetchSnapshot(
        connection: BridgeConnection,
        eventLimit: Int
    ) async throws -> BridgeSnapshot {
        BridgeSnapshot.empty
    }

    func fetchHealth(baseURL: URL) async throws -> BridgeHealth {
        BridgeHealth(
            status: "ok",
            startedAt: .now,
            uptimeMs: 1_000,
            sessionsCount: 0,
            eventsCount: 0,
            pendingDecisionsCount: 0,
            unresolvedDecisionsCount: 0,
            devicesCount: 0
        )
    }

    func submitDecision(
        connection: BridgeConnection,
        decisionID: String,
        decision: BridgeDecision
    ) async throws {
        if let submitError {
            throw submitError
        }

        submittedDecisions.append(
            SubmittedDecision(connection: connection, decisionID: decisionID, decision: decision)
        )
    }
}

private final class InMemoryConnectionStore: BridgeConnectionStore, @unchecked Sendable {
    private var connection: BridgeConnection?

    init(connection: BridgeConnection? = nil) {
        self.connection = connection
    }

    func save(_ connection: BridgeConnection) throws {
        self.connection = connection
    }

    func load() throws -> BridgeConnection? {
        connection
    }

    func remove() throws {
        connection = nil
    }
}

private final class InMemoryDecisionQueueStore: DecisionQueueStore, @unchecked Sendable {
    private var decisions: [QueuedDecision] = []

    func load() async throws -> [QueuedDecision] {
        decisions
    }

    func save(_ decisions: [QueuedDecision]) async throws {
        self.decisions = decisions
    }
}

private final class FakeLocalAuthenticator: LocalAuthenticating, @unchecked Sendable {
    private(set) var didAuthenticate = false

    func authenticate(reason: String) async throws {
        didAuthenticate = true
    }
}

private struct FakeNotificationAuthorizationCenter: NotificationAuthorizing {
    let granted: Bool

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        granted
    }
}

private struct FakeRemoteNotificationRegistrar: RemoteNotificationRegistering {
    @MainActor
    func registerForRemoteNotifications() {}
}
