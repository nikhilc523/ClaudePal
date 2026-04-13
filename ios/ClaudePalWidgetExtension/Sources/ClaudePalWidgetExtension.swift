import ActivityKit
import ClaudePalKit
import SwiftUI
import WidgetKit

// MARK: - Widget Colors (matching app theme)

private enum WC {
    static let bg = Color(red: 0.06, green: 0.06, blue: 0.10)
    static let card = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let accent = Color(red: 0.83, green: 0.58, blue: 0.42)
    static let accentGold = Color(red: 0.95, green: 0.65, blue: 0.35)
    static let approve = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let warning = Color(red: 0.96, green: 0.72, blue: 0.26)
    static let deny = Color(red: 0.93, green: 0.36, blue: 0.36)
    static let secondary = Color(red: 0.61, green: 0.54, blue: 0.87)
    static let textPrimary = Color.white
    static let textSecondary = Color.white.opacity(0.6)
    static let textTertiary = Color.white.opacity(0.38)
    static let border = Color.white.opacity(0.08)
}

// MARK: - Timeline Entry

struct ClaudePalEntry: TimelineEntry {
    let date: Date
    let activeSessions: Int
    let pendingApprovals: Int
    let totalEvents: Int
    let sessionName: String?
    let sessionStatus: String

    static let placeholder = ClaudePalEntry(
        date: .now, activeSessions: 1, pendingApprovals: 2,
        totalEvents: 12, sessionName: "MyProject", sessionStatus: "active"
    )

    static let empty = ClaudePalEntry(
        date: .now, activeSessions: 0, pendingApprovals: 0,
        totalEvents: 0, sessionName: nil, sessionStatus: "idle"
    )
}

// MARK: - Timeline Provider

struct ClaudePalProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudePalEntry { .placeholder }

    func getSnapshot(in context: Context, completion: @escaping (ClaudePalEntry) -> Void) {
        completion(context.isPreview ? .placeholder : .placeholder)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudePalEntry>) -> Void) {
        // TODO: Read real data from shared UserDefaults/App Group when CloudKit is wired
        let entry = ClaudePalEntry.placeholder
        completion(Timeline(entries: [entry], policy: .after(Date().addingTimeInterval(60))))
    }
}

// MARK: - Small Widget

struct SmallWidgetView: View {
    let entry: ClaudePalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mascot face + title
            HStack(spacing: 6) {
                MiniMascot()
                Text("ClaudePal")
                    .font(.system(size: 13, weight: .heavy, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(colors: [WC.accent, WC.accentGold],
                                       startPoint: .leading, endPoint: .trailing)
                    )
            }

            Spacer()

            // Pending count (hero number)
            if entry.pendingApprovals > 0 {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("\(entry.pendingApprovals)")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(WC.warning)
                    Text("pending")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(WC.textSecondary)
                }
            } else {
                Text("All clear")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(WC.approve)
            }

            // Session status
            HStack(spacing: 4) {
                Circle()
                    .fill(statusColor(entry.sessionStatus))
                    .frame(width: 6, height: 6)
                Text(entry.sessionName ?? "Idle")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(WC.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

// MARK: - Medium Widget

struct MediumWidgetView: View {
    let entry: ClaudePalEntry

    var body: some View {
        HStack(spacing: 16) {
            // Left: branding + session
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    MiniMascot()
                    Text("ClaudePal")
                        .font(.system(size: 14, weight: .heavy, design: .rounded))
                        .foregroundStyle(
                            LinearGradient(colors: [WC.accent, WC.accentGold],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                }

                Spacer()

                if let name = entry.sessionName {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(statusColor(entry.sessionStatus))
                            .frame(width: 6, height: 6)
                        Text(name)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(WC.textPrimary)
                    }
                    Text(entry.sessionStatus.capitalized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(WC.textTertiary)
                }
            }

            // Right: metric cards
            VStack(spacing: 6) {
                metricPill(icon: "bolt.fill", value: "\(entry.activeSessions)",
                           label: "Active", color: WC.approve)
                metricPill(icon: "bell.badge.fill", value: "\(entry.pendingApprovals)",
                           label: "Pending", color: WC.warning)
                metricPill(icon: "list.bullet", value: "\(entry.totalEvents)",
                           label: "Events", color: WC.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func metricPill(icon: String, value: String, label: String, color: Color) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(WC.textPrimary)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(WC.textSecondary)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(WC.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(WC.border, lineWidth: 0.5)
        )
    }
}

// MARK: - Lock Screen Widgets

struct InlineWidgetView: View {
    let entry: ClaudePalEntry

    var body: some View {
        if entry.pendingApprovals > 0 {
            Label("ClaudePal: \(entry.pendingApprovals) pending", systemImage: "bell.badge.fill")
        } else {
            Label("ClaudePal: All clear", systemImage: "checkmark.circle")
        }
    }
}

struct CircularWidgetView: View {
    let entry: ClaudePalEntry

    var body: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 1) {
                Text(">_<")
                    .font(.system(size: 11, weight: .black, design: .monospaced))
                Text("\(entry.pendingApprovals)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
            }
        }
    }
}

struct RectangularWidgetView: View {
    let entry: ClaudePalEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Text(">_<")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                Text("ClaudePal")
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
            }

            HStack(spacing: 12) {
                Label("\(entry.activeSessions)", systemImage: "bolt.fill")
                    .font(.system(size: 11, weight: .semibold))
                Label("\(entry.pendingApprovals)", systemImage: "bell.badge.fill")
                    .font(.system(size: 11, weight: .semibold))
            }

            if let name = entry.sessionName {
                Text(name + " \u{2022} " + entry.sessionStatus.capitalized)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Mini Mascot (for widgets)

private struct MiniMascot: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(WC.card)
                .frame(width: 20, height: 20)
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(WC.accent.opacity(0.3), lineWidth: 0.5)
                .frame(width: 20, height: 20)

            // Dots
            HStack(spacing: 1.5) {
                Circle().fill(WC.deny.opacity(0.8)).frame(width: 2, height: 2)
                Circle().fill(WC.warning.opacity(0.8)).frame(width: 2, height: 2)
                Circle().fill(WC.approve.opacity(0.8)).frame(width: 2, height: 2)
            }
            .offset(y: -5.5)

            // Face
            Text(">_<")
                .font(.system(size: 6, weight: .black, design: .monospaced))
                .foregroundStyle(WC.accent)
                .offset(y: 1.5)
        }
    }
}

// MARK: - Helper

private func statusColor(_ status: String) -> Color {
    switch status {
    case "active": WC.approve
    case "waiting": WC.warning
    case "idle": WC.textTertiary
    case "completed": WC.secondary
    case "failed": WC.deny
    default: WC.textTertiary
    }
}

// MARK: - Widget Definitions

struct ClaudePalStatusWidget: Widget {
    let kind = "ClaudePalStatus"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudePalProvider()) { entry in
            if #available(iOS 17.0, *) {
                SmallWidgetView(entry: entry)
                    .containerBackground(WC.bg, for: .widget)
            } else {
                SmallWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("ClaudePal Status")
        .description("Session status and pending approvals.")
        .supportedFamilies([.systemSmall])
    }
}

struct ClaudePalDashWidget: Widget {
    let kind = "ClaudePalDash"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudePalProvider()) { entry in
            if #available(iOS 17.0, *) {
                MediumWidgetView(entry: entry)
                    .containerBackground(WC.bg, for: .widget)
            } else {
                MediumWidgetView(entry: entry)
            }
        }
        .configurationDisplayName("ClaudePal Dashboard")
        .description("Full dashboard with sessions and metrics.")
        .supportedFamilies([.systemMedium])
    }
}

struct LockScreenWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: ClaudePalEntry

    var body: some View {
        switch family {
        case .accessoryInline:
            InlineWidgetView(entry: entry)
        case .accessoryCircular:
            CircularWidgetView(entry: entry)
        case .accessoryRectangular:
            RectangularWidgetView(entry: entry)
        default:
            CircularWidgetView(entry: entry)
        }
    }
}

struct ClaudePalLockScreenWidget: Widget {
    let kind = "ClaudePalLockScreen"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudePalProvider()) { entry in
            LockScreenWidgetView(entry: entry)
        }
        .configurationDisplayName("ClaudePal")
        .description("Quick glance at pending approvals.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

struct ClaudePalLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClaudePalActivityAttributes.self) { context in
            // Lock screen banner
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        MiniMascot()
                        Text(context.attributes.displayName)
                            .font(.headline)
                            .foregroundStyle(.primary)
                    }
                    Text(context.state.detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 6) {
                    Text(context.state.status.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(statusColor(context.state.status), in: Capsule())
                    if context.state.pendingApprovals > 0 {
                        Label("\(context.state.pendingApprovals)", systemImage: "bell.badge.fill")
                            .font(.caption)
                            .foregroundStyle(WC.warning)
                    }
                }
            }
            .padding()
            .activityBackgroundTint(WC.bg)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 4) {
                        Text(">_<")
                            .font(.system(size: 10, weight: .black, design: .monospaced))
                            .foregroundStyle(WC.accent)
                        Text(context.attributes.displayName)
                            .font(.headline)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.status.capitalized)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(statusColor(context.state.status))
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.detail)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        if context.state.pendingApprovals > 0 {
                            Label("\(context.state.pendingApprovals) pending", systemImage: "bell.badge.fill")
                                .font(.caption)
                                .foregroundStyle(WC.warning)
                        }
                    }
                }
            } compactLeading: {
                Text(">_<")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(WC.accent)
            } compactTrailing: {
                Text("\(context.state.pendingApprovals)")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(context.state.pendingApprovals > 0 ? WC.warning : WC.approve)
            } minimal: {
                Circle()
                    .fill(statusColor(context.state.status))
                    .frame(width: 10, height: 10)
            }
        }
    }
}

// MARK: - Widget Bundle

@main
struct ClaudePalWidgetExtension: WidgetBundle {
    var body: some Widget {
        ClaudePalStatusWidget()
        ClaudePalDashWidget()
        ClaudePalLockScreenWidget()
        ClaudePalLiveActivityWidget()
    }
}
