import ClaudePalKit
import Foundation
import SwiftUI

@MainActor @Observable
final class AppModel {
    let dataProvider: any DataProvider
    let localAuthenticator: LocalAuthenticating

    var banner: InAppBanner?
    var selectedTab: Tab = .dashboard

    enum Tab: Hashable {
        case dashboard, history, settings
    }

    // Forwarded from dataProvider
    var sessions: [Session] { dataProvider.sessions }
    var pendingDecisions: [PendingDecision] {
        dataProvider.pendingDecisions.filter { $0.status == .pending }
    }
    var recentEvents: [Event] { dataProvider.recentEvents }
    var connectionState: ConnectionState { dataProvider.connectionState }

    var activeSessions: [Session] {
        sessions.filter { $0.status == .active || $0.status == .waiting }
    }

    @ObservationIgnored
    var alwaysRequireFaceID: Bool {
        get { UserDefaults.standard.bool(forKey: "alwaysRequireFaceID") }
        set { UserDefaults.standard.set(newValue, forKey: "alwaysRequireFaceID") }
    }

    init(dataProvider: any DataProvider = MockDataProvider(),
         localAuthenticator: LocalAuthenticating = SystemLocalAuthenticator()) {
        self.dataProvider = dataProvider
        self.localAuthenticator = localAuthenticator
    }

    func bootstrap() async {
        await dataProvider.start()
    }

    func refresh() async {
        await dataProvider.refresh()
    }

    // MARK: - Approval Actions

    func approve(decision: PendingDecision) async {
        if decision.isDestructive || alwaysRequireFaceID {
            do {
                try await localAuthenticator.authenticate(
                    reason: "Authenticate to approve: \(decision.toolName ?? "tool action")"
                )
            } catch {
                showBanner(title: "Authentication Required",
                           message: "Face ID is needed to approve this action.",
                           style: .warning)
                return
            }
        }

        do {
            try await dataProvider.approve(decisionId: decision.id)
            showBanner(title: "Approved", message: decision.toolName ?? "Action approved", style: .success)
        } catch {
            showBanner(title: "Error", message: "Failed to approve: \(error.localizedDescription)", style: .error)
        }
    }

    func deny(decision: PendingDecision, reason: String? = nil) async {
        do {
            try await dataProvider.deny(decisionId: decision.id, reason: reason)
            showBanner(title: "Denied", message: decision.toolName ?? "Action denied", style: .info)
        } catch {
            showBanner(title: "Error", message: "Failed to deny: \(error.localizedDescription)", style: .error)
        }
    }

    func events(for session: Session) -> [Event] {
        dataProvider.events(for: session.id)
    }

    func session(for decision: PendingDecision) -> Session? {
        sessions.first { $0.id == decision.sessionId }
    }

    // MARK: - Banner

    private func showBanner(title: String, message: String, style: InAppBanner.Style) {
        banner = InAppBanner(title: title, message: message, style: style)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if banner?.title == title { banner = nil }
        }
    }
}

// MARK: - Banner Model

struct InAppBanner: Equatable {
    let title: String
    let message: String
    let style: Style

    enum Style: Equatable {
        case success, error, warning, info

        var color: Color {
            switch self {
            case .success: .green
            case .error: .red
            case .warning: .orange
            case .info: .blue
            }
        }

        var icon: String {
            switch self {
            case .success: "checkmark.circle.fill"
            case .error: "xmark.circle.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .info: "info.circle.fill"
            }
        }
    }
}
