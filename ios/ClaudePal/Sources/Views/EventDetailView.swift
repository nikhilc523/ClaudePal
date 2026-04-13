import ClaudePalKit
import SwiftUI

struct EventDetailView: View {
    let event: Event
    let session: Session?

    var body: some View {
        ScrollView {
            VStack(spacing: CPSpacing.xl) {
                // Event info
                VStack(alignment: .leading, spacing: CPSpacing.md) {
                    CPSectionHeader(title: "Event")

                    VStack(spacing: 0) {
                        detailRow(icon: "tag.fill", label: "Type", value: event.type.rawValue)
                        Divider().background(Color.cpDivider)
                        detailRow(icon: "text.quote", label: "Title", value: event.title)
                        if !event.message.isEmpty {
                            Divider().background(Color.cpDivider)
                            detailRow(icon: "text.alignleft", label: "Message", value: event.message)
                        }
                        Divider().background(Color.cpDivider)
                        detailRow(icon: "clock.fill", label: "Time", value: event.createdAt.formatted(.dateTime))
                    }
                    .cpCard()
                }

                // Session info
                if let session {
                    VStack(alignment: .leading, spacing: CPSpacing.md) {
                        CPSectionHeader(title: "Session")

                        VStack(spacing: 0) {
                            detailRow(icon: "folder.fill", label: "Name", value: session.displayName)
                            Divider().background(Color.cpDivider)
                            detailRow(icon: "circle.fill", label: "Status", value: session.status.rawValue.capitalized)
                            Divider().background(Color.cpDivider)
                            detailRow(icon: "terminal", label: "Directory", value: session.cwd)
                        }
                        .cpCard()
                    }
                }

                // Payload
                if let payload = event.payload, !payload.isEmpty {
                    VStack(alignment: .leading, spacing: CPSpacing.md) {
                        CPSectionHeader(title: "Payload")

                        Text(payload)
                            .font(CPFont.mono)
                            .foregroundStyle(Color.cpTextSecondary)
                            .textSelection(.enabled)
                            .padding(CPSpacing.lg)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.cpCard, in: RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                                    .stroke(CPGradient.cardBorder, lineWidth: 0.5)
                            )
                    }
                }
            }
            .padding(CPSpacing.lg)
            .padding(.bottom, 40)
        }
        .background(Color.cpBackground)
        .navigationTitle(event.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarColorScheme(.dark, for: .navigationBar)
    }

    private func detailRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: CPSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.cpAccent)
                .frame(width: 24)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Color.cpTextSecondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .foregroundStyle(Color.cpTextPrimary)
                .multilineTextAlignment(.trailing)
                .lineLimit(3)
        }
        .padding(.horizontal, CPSpacing.lg)
        .padding(.vertical, CPSpacing.md)
    }
}
