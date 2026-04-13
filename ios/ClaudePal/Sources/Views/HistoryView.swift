import SwiftUI
import ClaudePalKit

struct HistoryView: View {
    @Bindable var model: AppModel
    @State private var selectedType: EventType?
    @State private var searchText = ""

    var filteredEvents: [Event] {
        model.recentEvents.filter { event in
            if let type = selectedType, event.type != type { return false }
            if !searchText.isEmpty {
                let q = searchText.lowercased()
                return event.title.lowercased().contains(q) || event.message.lowercased().contains(q)
            }
            return true
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CPSpacing.md) {
                    // Filter chips
                    filterChips

                    if filteredEvents.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: CPSpacing.sm) {
                            ForEach(filteredEvents) { event in
                                NavigationLink {
                                    EventDetailView(event: event,
                                                    session: model.sessions.first { $0.id == event.sessionId })
                                } label: {
                                    EventRow(event: event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(.horizontal, CPSpacing.lg)
                .padding(.top, CPSpacing.md)
                .padding(.bottom, 100)
            }
            .background(Color.cpBackground)
            .navigationTitle("History")
            .toolbarColorScheme(.dark, for: .navigationBar)
            .searchable(text: $searchText, prompt: "Search events")
        }
    }

    // MARK: - Filter Chips

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                filterChip(label: "All", type: nil)
                filterChip(label: "Permissions", type: .permissionRequested)
                filterChip(label: "Completed", type: .taskCompleted)
                filterChip(label: "Started", type: .sessionStarted)
                filterChip(label: "Notifications", type: .notificationReceived)
                filterChip(label: "Errors", type: .errorReceived)
            }
        }
    }

    private func filterChip(label: String, type: EventType?) -> some View {
        Button {
            withAnimation(.spring(response: 0.25)) { selectedType = type }
            CPHaptics.light()
        } label: {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(selectedType == type ? .white : Color.cpTextSecondary)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    selectedType == type
                        ? AnyShapeStyle(Color.cpAccent)
                        : AnyShapeStyle(Color.cpCard),
                    in: Capsule()
                )
                .overlay(
                    Capsule().stroke(
                        selectedType == type ? Color.clear : Color.cpDivider,
                        lineWidth: 0.5
                    )
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: CPSpacing.lg) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 40))
                .foregroundStyle(Color.cpTextTertiary)
            Text("No Events")
                .font(CPFont.cardTitle)
                .foregroundStyle(Color.cpTextPrimary)
            Text("Events from Claude Code sessions will appear here.")
                .font(.caption)
                .foregroundStyle(Color.cpTextSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    }
}

// MARK: - Event Row

struct EventRow: View {
    let event: Event

    var body: some View {
        HStack(spacing: CPSpacing.md) {
            Image(systemName: eventIcon)
                .font(.system(size: 15))
                .foregroundStyle(eventColor)
                .frame(width: 28, height: 28)
                .background(eventColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Color.cpTextPrimary)
                if !event.message.isEmpty {
                    Text(event.message)
                        .font(CPFont.mono)
                        .foregroundStyle(Color.cpTextTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text(timeAgo(event.createdAt))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(Color.cpTextTertiary)
        }
        .padding(CPSpacing.md)
        .background(Color.cpCard, in: RoundedRectangle(cornerRadius: CPRadius.sm, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: CPRadius.sm, style: .continuous)
                .stroke(CPGradient.cardBorder, lineWidth: 0.5)
        )
    }

    private var eventIcon: String {
        switch event.type {
        case .permissionRequested: "lock.shield.fill"
        case .taskCompleted: "checkmark.circle.fill"
        case .sessionStarted: "play.circle.fill"
        case .sessionEnded: "stop.circle.fill"
        case .sessionUpdated: "arrow.clockwise.circle.fill"
        case .notificationReceived: "bell.fill"
        case .errorReceived: "exclamationmark.circle.fill"
        case .inputRequested: "text.cursor"
        case .taskCreated: "plus.circle.fill"
        }
    }

    private var eventColor: Color {
        switch event.type {
        case .permissionRequested: .cpWarning
        case .taskCompleted: .cpApprove
        case .errorReceived: .cpDeny
        case .sessionStarted: .cpSecondary
        default: Color.cpTextTertiary
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let s = Int(-date.timeIntervalSinceNow)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86400 { return "\(s / 3600)h" }
        return "\(s / 86400)d"
    }
}
