import SwiftUI
import ClaudePalKit

struct SettingsView: View {
    @Bindable var model: AppModel
    @AppStorage("alwaysRequireFaceID") private var alwaysRequireFaceID = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: CPSpacing.sectionGap) {
                    syncSection
                    securitySection
                    aboutSection
                }
                .padding(.horizontal, CPSpacing.lg)
                .padding(.top, CPSpacing.md)
                .padding(.bottom, 100)
            }
            .background(Color.cpBackground)
            .navigationTitle("Settings")
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }

    // MARK: - Sync

    private var syncSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            CPSectionHeader(title: "Sync")

            VStack(spacing: 0) {
                settingsRow(icon: "icloud.fill", iconColor: .cpSecondary, title: "Status") {
                    HStack(spacing: 6) {
                        PulsingDot(color: model.connectionState.isConnected ? .cpApprove : .cpDeny,
                                   isAnimating: model.connectionState.isConnected)
                        Text(model.connectionState.displayText)
                            .font(.subheadline)
                            .foregroundStyle(Color.cpTextSecondary)
                    }
                }

                Divider().background(Color.cpDivider)

                settingsRow(icon: "bolt.fill", iconColor: .cpApprove, title: "Sessions") {
                    Text("\(model.sessions.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.cpTextSecondary)
                }

                Divider().background(Color.cpDivider)

                settingsRow(icon: "bell.badge.fill", iconColor: .cpWarning, title: "Pending") {
                    Text("\(model.pendingDecisions.count)")
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Color.cpTextSecondary)
                }
            }
            .cpCard()
        }
    }

    // MARK: - Security

    private var securitySection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            CPSectionHeader(title: "Security")

            VStack(spacing: 0) {
                HStack(spacing: CPSpacing.md) {
                    Image(systemName: "faceid")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.cpAccent)
                        .frame(width: 28)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Face ID for All Approvals")
                            .font(.subheadline)
                            .foregroundStyle(Color.cpTextPrimary)
                        Text("Require authentication for every approval, not just destructive ones.")
                            .font(.caption2)
                            .foregroundStyle(Color.cpTextTertiary)
                    }
                    Spacer()
                    Toggle("", isOn: $alwaysRequireFaceID)
                        .labelsHidden()
                        .tint(Color.cpAccent)
                }
                .padding(CPSpacing.lg)
            }
            .background(Color.cpCard, in: RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                    .stroke(CPGradient.cardBorder, lineWidth: 0.5)
            )
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        VStack(alignment: .leading, spacing: CPSpacing.md) {
            CPSectionHeader(title: "About")

            VStack(spacing: 0) {
                settingsRow(icon: "info.circle.fill", iconColor: Color.cpTextTertiary, title: "Version") {
                    Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—")
                        .font(.subheadline)
                        .foregroundStyle(Color.cpTextSecondary)
                }

                Divider().background(Color.cpDivider)

                settingsRow(icon: "hammer.fill", iconColor: Color.cpTextTertiary, title: "Build") {
                    Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")
                        .font(.subheadline)
                        .foregroundStyle(Color.cpTextSecondary)
                }
            }
            .cpCard()
        }
    }

    // MARK: - Helpers

    private func settingsRow<Trailing: View>(icon: String, iconColor: Color, title: String,
                                              @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: CPSpacing.md) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(iconColor)
                .frame(width: 28)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Color.cpTextPrimary)
            Spacer()
            trailing()
        }
        .padding(.horizontal, CPSpacing.lg)
        .padding(.vertical, CPSpacing.md)
    }
}
