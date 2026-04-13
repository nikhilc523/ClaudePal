import SwiftUI
import ClaudePalKit

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        ZStack(alignment: .bottom) {
            // Content
            Group {
                switch model.selectedTab {
                case .dashboard:
                    DashboardView(model: model)
                case .history:
                    HistoryView(model: model)
                case .settings:
                    SettingsView(model: model)
                }
            }

            // Custom tab bar
            customTabBar

            // Banner overlay
            if let banner = model.banner {
                VStack {
                    BannerView(banner: banner)
                        .transition(.move(edge: .top).combined(with: .opacity))
                    Spacer()
                }
                .padding(.top, 60)
                .animation(.spring(response: 0.3), value: model.banner)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Custom Tab Bar

    private var customTabBar: some View {
        HStack(spacing: 0) {
            tabItem(icon: "square.grid.2x2.fill", label: "Dashboard", tab: .dashboard)
            tabItem(icon: "clock.fill", label: "History", tab: .history)
            tabItem(icon: "gearshape.fill", label: "Settings", tab: .settings)
        }
        .padding(.horizontal, CPSpacing.xl)
        .padding(.vertical, CPSpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: CPRadius.hero, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: .black.opacity(0.4), radius: 20, y: -4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CPRadius.hero, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 0.5)
        )
        .padding(.horizontal, 40)
        .padding(.bottom, 8)
    }

    private func tabItem(icon: String, label: String, tab: AppModel.Tab) -> some View {
        Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                model.selectedTab = tab
                CPHaptics.light()
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(model.selectedTab == tab ? Color.cpAccent : Color.cpTextTertiary)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(model.selectedTab == tab ? Color.cpAccent : Color.cpTextTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Banner

struct BannerView: View {
    let banner: InAppBanner

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: banner.style.icon)
                .foregroundStyle(banner.style.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(banner.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Color.cpTextPrimary)
                Text(banner.message)
                    .font(.caption)
                    .foregroundStyle(Color.cpTextSecondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                .stroke(CPGradient.cardBorder, lineWidth: 0.5)
        )
        .padding(.horizontal, CPSpacing.lg)
    }
}
