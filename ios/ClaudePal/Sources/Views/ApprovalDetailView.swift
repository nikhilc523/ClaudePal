import ClaudePalKit
import SwiftUI

struct ApprovalDetailView: View {
    @Bindable var model: AppModel
    let decision: PendingDecision
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: CPSpacing.xl) {
                // Destructive warning
                if decision.isDestructive {
                    destructiveWarning
                }

                // Tool info
                toolInfoCard

                // Session context
                if let session = model.session(for: decision) {
                    sessionContextCard(session)
                }

                // Expiry
                expiryCard

                Spacer(minLength: 24)

                // Action buttons
                actionButtons
            }
            .padding(CPSpacing.lg)
        }
        .background(Color.cpBackground)
        .navigationTitle(decision.toolName ?? "Approval")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Destructive Warning

    private var destructiveWarning: some View {
        HStack(spacing: CPSpacing.md) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.title3)
                .foregroundStyle(Color.cpDeny)
            VStack(alignment: .leading, spacing: 2) {
                Text("Destructive Action")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cpDeny)
                Text("Face ID required to approve.")
                    .font(.caption)
                    .foregroundStyle(Color.cpTextSecondary)
            }
            Spacer()
            Image(systemName: "faceid")
                .font(.title2)
                .foregroundStyle(Color.cpDeny.opacity(0.6))
        }
        .padding(CPSpacing.lg)
        .background(
            RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                .fill(Color.cpDeny.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                .stroke(Color.cpDeny.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Tool Info

    private var toolInfoCard: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            HStack(spacing: 8) {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.cpAccent)
                Text("Tool")
                    .font(CPFont.sectionHeader)
                    .foregroundStyle(Color.cpAccent)
                    .tracking(0.8)
            }

            Text(decision.toolName ?? "Unknown")
                .font(.title2.weight(.bold))
                .foregroundStyle(Color.cpTextPrimary)

            if let input = decision.toolInput {
                Text("INPUT")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Color.cpTextTertiary)
                    .tracking(0.8)
                    .padding(.top, 4)

                Text(input)
                    .font(CPFont.mono)
                    .foregroundStyle(Color.cpTextSecondary)
                    .padding(CPSpacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.cpBackground, in: RoundedRectangle(cornerRadius: 10))
            }
        }
        .cpCard()
    }

    // MARK: - Session Context

    private func sessionContextCard(_ session: Session) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: CPSpacing.xs) {
                HStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.cpSecondary)
                    Text("SESSION")
                        .font(.system(size: 10, weight: .heavy))
                        .foregroundStyle(Color.cpSecondary)
                        .tracking(0.8)
                }
                Text(session.displayName)
                    .font(CPFont.cardTitle)
                    .foregroundStyle(Color.cpTextPrimary)
                Text(session.cwd)
                    .font(.caption2)
                    .foregroundStyle(Color.cpTextTertiary)
            }
            Spacer()
            Text(session.status.rawValue.capitalized)
                .font(.caption.weight(.medium))
                .foregroundStyle(Color.cpAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.cpAccent.opacity(0.12), in: Capsule())
        }
        .cpCard()
    }

    // MARK: - Expiry

    private var expiryCard: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.cpTextTertiary)
                Text("Expires")
                    .font(.caption)
                    .foregroundStyle(Color.cpTextSecondary)
            }
            Spacer()
            ExpiryCountdown(expiresAt: decision.expiresAt)
        }
        .cpCard()
    }

    // MARK: - Actions

    private var actionButtons: some View {
        VStack(spacing: CPSpacing.md) {
            Button {
                Task {
                    CPHaptics.medium()
                    await model.approve(decision: decision)
                    dismiss()
                }
            } label: {
                HStack(spacing: 8) {
                    if decision.isDestructive {
                        Image(systemName: "faceid")
                    }
                    Text("Approve")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(CPPrimaryButtonStyle(color: .cpApprove))

            Button {
                Task {
                    CPHaptics.light()
                    await model.deny(decision: decision)
                    dismiss()
                }
            } label: {
                Text("Deny")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(CPSecondaryButtonStyle(color: .cpDeny))
        }
    }
}
