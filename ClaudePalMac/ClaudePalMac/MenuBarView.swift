import SwiftUI
import ClaudePalMacCore

/// The dropdown content shown when the menu bar icon is clicked.
struct MenuBarView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection

            Divider()

            // Pending approvals
            if !appState.pendingDecisions.isEmpty {
                pendingSection
                Divider()
            }

            // Active sessions
            if !appState.sessions.isEmpty {
                sessionsSection
                Divider()
            }

            // Controls
            controlsSection
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            Image(systemName: appState.statusIcon)
                .foregroundStyle(appState.pendingCount > 0 ? .orange : .green)
            Text("ClaudePal")
                .font(.headline)
            Spacer()
            Text(appState.serverRunning ? "Running" : "Stopped")
                .font(.caption)
                .foregroundColor(appState.serverRunning ? .secondary : .red)
        }
        .padding(12)
    }

    // MARK: - Pending Approvals

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("PENDING APPROVALS")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(appState.pendingDecisions) { decision in
                PendingDecisionRow(decision: decision, appState: appState)
            }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("SESSIONS")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.top, 8)
                .padding(.bottom, 4)

            ForEach(appState.sessions.prefix(5)) { session in
                SessionRow(session: session)
            }
        }
    }

    // MARK: - Controls

    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if appState.hooksInstalled {
                Button {
                    appState.uninstallHooks()
                } label: {
                    Label("Uninstall Hooks", systemImage: "xmark.circle")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            } else {
                Button {
                    appState.installHooks()
                } label: {
                    Label("Install Hooks", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }

            Button {
                appState.toggleLaunchOnLogin()
            } label: {
                HStack {
                    Label("Launch on Login", systemImage: "power")
                    Spacer()
                    if appState.launchOnLogin {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.blue)
                    }
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider()

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit ClaudePal", systemImage: "power")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Pending Decision Row

struct PendingDecisionRow: View {
    let decision: PendingDecision
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if decision.isDestructive {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                }
                Text(decision.toolName ?? "Unknown Tool")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Spacer()
                Text(timeAgo(decision.createdAt))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let input = decision.toolInput {
                Text(input.prefix(120) + (input.count > 120 ? "..." : ""))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    appState.approve(decision: decision)
                } label: {
                    Text("Approve")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button {
                    appState.deny(decision: decision)
                } label: {
                    Text("Deny")
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(decision.isDestructive ? Color.red.opacity(0.05) : Color.clear)
    }

    private func timeAgo(_ date: Date) -> String {
        let seconds = Int(-date.timeIntervalSinceNow)
        if seconds < 60 { return "\(seconds)s ago" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        return "\(seconds / 3600)h ago"
    }
}

// MARK: - Session Row

struct SessionRow: View {
    let session: Session

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(session.displayName)
                .font(.subheadline)
            Spacer()
            Text(session.status.rawValue)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .green
        case .waiting: .orange
        case .idle: .gray
        case .completed: .blue
        case .failed: .red
        }
    }
}
