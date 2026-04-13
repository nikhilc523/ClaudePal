import SwiftUI
import ClaudePalMacCore

/// Expanded notch panel — compact macOS scale, mirrors iOS design language.
struct NotchExpandedView: View {
    @ObservedObject var appState: AppState
    var onApprove: (PendingDecision) -> Void
    var onDeny: (PendingDecision) -> Void
    var onCollapse: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            headerRow
            metricsRow
            divider

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 8) {
                    if !appState.pendingDecisions.isEmpty {
                        pendingSection
                    }
                    if !appState.sessions.isEmpty {
                        sessionsSection
                    }
                    if appState.pendingDecisions.isEmpty && appState.sessions.isEmpty {
                        idleSection
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .frame(maxHeight: 280)
        }
        .frame(width: 320)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 6) {
            TerminalMascot(size: 20, animated: true)

            Text("ClaudePal")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(
                    LinearGradient(
                        colors: [Color.cpAccent, Color(red: 0.95, green: 0.65, blue: 0.35)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )

            Spacer()

            HStack(spacing: 3) {
                NotchPulsingDot(color: appState.serverRunning ? .cpApprove : .cpDeny,
                                isAnimating: appState.serverRunning, dotSize: 4, pulseSize: 8)
                Text(appState.serverRunning ? "Connected" : "Offline")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.cpTextTertiary)
            }

            Button { onCollapse() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(Color.cpTextTertiary)
                    .frame(width: 14, height: 14)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .padding(.bottom, 6)
    }

    // MARK: - Metrics

    private var metricsRow: some View {
        HStack(spacing: 6) {
            NotchMetricTile(title: "Active",
                            value: "\(appState.sessions.filter { $0.status == .active }.count)",
                            icon: "bolt.fill", color: .cpApprove)
            NotchMetricTile(title: "Pending",
                            value: "\(appState.pendingDecisions.count)",
                            icon: "bell.badge.fill", color: .cpWarning)
            NotchMetricTile(title: "Sessions",
                            value: "\(appState.sessions.count)",
                            icon: "terminal.fill", color: .cpSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 6)
    }

    private var divider: some View {
        Color.cpDivider.frame(height: 0.5).padding(.horizontal, 10)
    }

    // MARK: - Pending

    private var pendingSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "bell.badge.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.cpAccent)
                Text("PENDING")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.cpAccent)
                    .tracking(0.8)
                VStack { Divider().background(Color.cpAccent.opacity(0.2)) }
                Text("\(appState.pendingDecisions.count)")
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.cpWarning, in: Capsule())
            }

            ForEach(Array(appState.pendingDecisions.prefix(3))) { decision in
                NotchPendingCard(decision: decision, onApprove: onApprove, onDeny: onDeny)
            }

            if appState.pendingDecisions.count > 3 {
                Text("+\(appState.pendingDecisions.count - 3) more")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color.cpTextTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Sessions

    private var sessionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(Color.cpAccent)
                Text("SESSIONS")
                    .font(.system(size: 8, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.cpAccent)
                    .tracking(0.8)
                VStack { Divider().background(Color.cpAccent.opacity(0.2)) }
            }

            ForEach(Array(appState.sessions.prefix(3))) { session in
                NotchSessionCard(session: session)
            }
        }
    }

    // MARK: - Idle

    private var idleSection: some View {
        VStack(spacing: 6) {
            TerminalMascot(size: 32, animated: true)
            Text("All quiet")
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(Color.cpTextTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }
}

// MARK: - Pending Card

private struct NotchPendingCard: View {
    let decision: PendingDecision
    var onApprove: (PendingDecision) -> Void
    var onDeny: (PendingDecision) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: decision.isDestructive ? "exclamationmark.triangle.fill" : "terminal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(decision.isDestructive ? Color.cpDeny : Color.cpAccent)
                Text(decision.toolName ?? "Unknown")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cpTextPrimary)
                Spacer()
                Text(timeAgo(decision.createdAt))
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color.cpTextTertiary)
            }

            if let input = decision.toolInput {
                Text(formatToolInput(input))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(Color.cpTextSecondary)
                    .lineLimit(2)
                    .padding(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cpBackground.opacity(0.6), in: RoundedRectangle(cornerRadius: 5))
            }

            HStack(spacing: 4) {
                Button { onApprove(decision) } label: {
                    Text("Approve")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2.5)
                        .background(Color.cpApprove, in: Capsule())
                }
                .buttonStyle(.plain)

                Button { onDeny(decision) } label: {
                    Text("Deny")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(Color.cpDeny)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2.5)
                        .background(Color.cpDeny.opacity(0.12), in: Capsule())
                        .overlay(Capsule().stroke(Color.cpDeny.opacity(0.2), lineWidth: 0.5))
                }
                .buttonStyle(.plain)

                Spacer()
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(decision.isDestructive ? Color.cpDeny.opacity(0.06) : Color.cpCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: decision.isDestructive
                            ? [Color.cpDeny.opacity(0.15), Color.cpDeny.opacity(0.05)]
                            : [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }

    private func formatToolInput(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let cmd = json["command"] as? String { return "$ \(cmd)" }
            if let fp = json["file_path"] as? String { return fp }
            if let p = json["pattern"] as? String { return p }
        }
        return String(raw.prefix(100))
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        return "\(s / 3600)h"
    }
}

// MARK: - Session Card

private struct NotchSessionCard: View {
    let session: Session

    var body: some View {
        HStack(spacing: 8) {
            NotchPulsingDot(color: statusColor, isAnimating: session.status == .active,
                            dotSize: 5, pulseSize: 10)

            VStack(alignment: .leading, spacing: 0) {
                Text(session.displayName)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.cpTextPrimary)
                    .lineLimit(1)
                Text(session.cwd)
                    .font(.system(size: 8))
                    .foregroundStyle(Color.cpTextTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(session.status.rawValue.capitalized)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(statusColor)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.cpCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
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

private struct NotchMetricTile: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 7))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(Color.cpTextPrimary)
            Text(title)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(Color.cpTextSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .background(Color.cpCard, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 0.5
                )
        )
    }
}

// MARK: - Pulsing Dot

struct NotchPulsingDot: View {
    let color: Color
    var isAnimating: Bool = true
    var dotSize: CGFloat = 6
    var pulseSize: CGFloat = 12

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if isAnimating {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: pulseSize, height: pulseSize)
                    .scaleEffect(isPulsing ? 1.8 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            }
            Circle()
                .fill(color)
                .frame(width: dotSize, height: dotSize)
        }
        .frame(width: pulseSize, height: pulseSize)
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}
