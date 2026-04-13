import ClaudePalKit
import SwiftUI

struct DashboardView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CPSpacing.sectionGap) {
                    headerRow

                    metricsRow

                    if !model.pendingDecisions.isEmpty {
                        pendingSection
                    }

                    sessionsSection
                }
                .padding(.horizontal, CPSpacing.lg)
                .padding(.top, CPSpacing.md)
                .padding(.bottom, 40)
            }
            .background(Color.cpBackground)
            .refreshable { await model.refresh() }
            .navigationBarHidden(true)
        }
    }

    // MARK: - Header

    private var headerRow: some View {
        VStack(spacing: 8) {
            TerminalMascot(size: 52)

            Text("ClaudePal")
                .font(.system(size: 34, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.cpAccent, Color(red: 0.95, green: 0.65, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            HStack(spacing: 6) {
                PulsingDot(color: model.connectionState.isConnected ? .cpApprove : .cpDeny,
                           isAnimating: model.connectionState.isConnected)
                Text(model.connectionState.displayText)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(Color.cpTextSecondary)
            }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Pending Approvals

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            CPSectionHeader(title: "Pending", icon: "bell.badge.fill") {
                AnyView(
                    Text("\(model.pendingDecisions.count)")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.cpWarning, in: Capsule())
                )
            }

            ForEach(model.pendingDecisions) { decision in
                NavigationLink {
                    ApprovalDetailView(model: model, decision: decision)
                } label: {
                    PendingCard(decision: decision)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            CPSectionHeader(title: "Sessions", icon: "bolt.fill")

            if model.sessions.isEmpty {
                VStack(spacing: CPSpacing.md) {
                    Image(systemName: "moon.zzz.fill")
                        .font(.system(size: 28))
                        .foregroundStyle(Color.cpTextTertiary)
                    Text("No active sessions")
                        .font(CPFont.cardBody)
                        .foregroundStyle(Color.cpTextSecondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, CPSpacing.xxl)
                .cpCard()
            } else {
                ForEach(model.sessions) { session in
                    SessionCard(session: session)
                }
            }
        }
    }

    // MARK: - Metrics Row

    private var metricsRow: some View {
        HStack(spacing: CPSpacing.md) {
            MetricTile(title: "Active", value: "\(model.activeSessions.count)",
                       icon: "bolt.fill", color: .cpApprove)
            MetricTile(title: "Pending", value: "\(model.pendingDecisions.count)",
                       icon: "bell.badge.fill", color: .cpWarning)
            MetricTile(title: "Events", value: "\(model.recentEvents.count)",
                       icon: "list.bullet", color: .cpSecondary)
        }
    }
}

// MARK: - Pending Card

struct PendingCard: View {
    let decision: PendingDecision

    var body: some View {
        VStack(alignment: .leading, spacing: CPSpacing.sm) {
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: decision.isDestructive ? "exclamationmark.triangle.fill" : "terminal.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(decision.isDestructive ? Color.cpDeny : Color.cpAccent)

                    Text(decision.toolName ?? "Unknown")
                        .font(CPFont.cardTitle)
                        .foregroundStyle(Color.cpTextPrimary)
                }
                Spacer()
                HStack(spacing: 4) {
                    if decision.isDestructive {
                        Image(systemName: "faceid")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.cpDeny.opacity(0.7))
                    }
                    ExpiryCountdown(expiresAt: decision.expiresAt)
                }
            }

            if let input = decision.toolInput {
                Text(String(input.prefix(120)))
                    .font(CPFont.mono)
                    .foregroundStyle(Color.cpTextSecondary)
                    .lineLimit(2)
                    .padding(CPSpacing.sm)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cpBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .cpCard(elevated: decision.isDestructive)
        .overlay(
            RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                .stroke(decision.isDestructive ? Color.cpDeny.opacity(0.2) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: Session

    var body: some View {
        HStack(spacing: CPSpacing.md) {
            PulsingDot(color: statusColor, isAnimating: session.status == .active)

            VStack(alignment: .leading, spacing: 2) {
                Text(session.displayName)
                    .font(CPFont.cardTitle)
                    .foregroundStyle(Color.cpTextPrimary)
                Text(session.cwd)
                    .font(.caption2)
                    .foregroundStyle(Color.cpTextTertiary)
                    .lineLimit(1)
            }
            Spacer()
            Text(session.status.rawValue.capitalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .cpCard()
    }

    private var statusColor: Color {
        switch session.status {
        case .active: .cpApprove
        case .waiting: .cpWarning
        case .idle: Color.cpTextTertiary
        case .completed: .cpSecondary
        case .failed: .cpDeny
        }
    }
}

// MARK: - Metric Tile

struct MetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.cpTextPrimary)
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.cpTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Color.cpCard, in: RoundedRectangle(cornerRadius: CPRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CPRadius.sm, style: .continuous)
                .stroke(CPGradient.cardBorder, lineWidth: 0.5)
        )
    }
}

// MARK: - Expiry Countdown

struct ExpiryCountdown: View {
    let expiresAt: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let remaining = max(0, Int(expiresAt.timeIntervalSinceNow))
            Text("\(remaining)s")
                .font(.system(.caption, design: .monospaced, weight: .medium))
                .foregroundStyle(remaining < 30 ? Color.cpDeny : Color.cpTextTertiary)
        }
    }
}
