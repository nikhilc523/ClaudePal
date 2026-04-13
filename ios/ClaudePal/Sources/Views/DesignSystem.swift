import SwiftUI

// MARK: - Color Palette

extension Color {
    // MARK: Brand
    static let cpAccent = Color(red: 0.83, green: 0.58, blue: 0.42)
    static let cpAccentSubtle = cpAccent.opacity(0.15)
    static let cpSecondary = Color(red: 0.61, green: 0.54, blue: 0.87)
    static let cpSecondarySubtle = cpSecondary.opacity(0.15)

    // MARK: Semantic
    static let cpApprove = Color(red: 0.30, green: 0.78, blue: 0.55)
    static let cpDeny = Color(red: 0.93, green: 0.36, blue: 0.36)
    static let cpWarning = Color(red: 0.96, green: 0.72, blue: 0.26)

    // MARK: Surfaces
    static let cpBackground = Color(red: 0.04, green: 0.04, blue: 0.05)
    static let cpCard = Color(red: 0.10, green: 0.10, blue: 0.12)
    static let cpCardElevated = Color(red: 0.15, green: 0.15, blue: 0.16)
    static let cpDivider = Color.white.opacity(0.08)

    // MARK: Text
    static let cpTextPrimary = Color.white
    static let cpTextSecondary = Color.white.opacity(0.6)
    static let cpTextTertiary = Color.white.opacity(0.38)
}

// MARK: - Spacing

enum CPSpacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 28
    static let sectionGap: CGFloat = 28
}

// MARK: - Corner Radii

enum CPRadius {
    static let sm: CGFloat = 10
    static let md: CGFloat = 14
    static let lg: CGFloat = 18
    static let card: CGFloat = 16
    static let hero: CGFloat = 24
    static let pill: CGFloat = 100
}

// MARK: - Typography

enum CPFont {
    static let heroTitle = Font.system(.largeTitle, design: .default, weight: .bold)
    static let heroSubtitle = Font.system(.body, design: .default, weight: .medium)
    static let sectionHeader = Font.system(.footnote, design: .default, weight: .heavy)
    static let cardTitle = Font.system(.headline, design: .default, weight: .semibold)
    static let cardBody = Font.system(.subheadline, design: .default, weight: .regular)
    static let metric = Font.system(.title, design: .rounded, weight: .bold).monospacedDigit()
    static let metricLabel = Font.system(.caption, design: .default, weight: .medium)
    static let mono = Font.system(.caption, design: .monospaced, weight: .regular)
    static let monoBody = Font.system(.body, design: .monospaced, weight: .regular)
}

// MARK: - Gradients

enum CPGradient {
    static let hero = LinearGradient(
        colors: [
            Color(red: 0.52, green: 0.32, blue: 0.18),
            Color(red: 0.40, green: 0.28, blue: 0.48),
            Color(red: 0.30, green: 0.24, blue: 0.56),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let heroWatch = LinearGradient(
        colors: [Color(red: 0.45, green: 0.28, blue: 0.16), Color(red: 0.30, green: 0.24, blue: 0.48)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let approveButton = LinearGradient(
        colors: [Color.cpApprove, Color.cpApprove.opacity(0.8)],
        startPoint: .top,
        endPoint: .bottom
    )

    static let cardBorder = LinearGradient(
        colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - Card Modifier

struct CPCardModifier: ViewModifier {
    var elevated: Bool = false

    func body(content: Content) -> some View {
        content
            .padding(CPSpacing.lg)
            .background(
                RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                    .fill(elevated ? Color.cpCardElevated : Color.cpCard)
            )
            .overlay(
                RoundedRectangle(cornerRadius: CPRadius.card, style: .continuous)
                    .stroke(CPGradient.cardBorder, lineWidth: 0.5)
            )
    }
}

extension View {
    func cpCard(elevated: Bool = false) -> some View {
        modifier(CPCardModifier(elevated: elevated))
    }
}

// MARK: - Button Styles

struct CPPrimaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(color, in: Capsule())
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct CPSecondaryButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(color.opacity(0.12), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25), lineWidth: 0.5))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Section Header

struct CPSectionHeader: View {
    let title: String
    var icon: String? = nil
    var trailing: (() -> AnyView)? = nil

    var body: some View {
        HStack(spacing: 8) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.cpAccent)
            }

            Text(title.uppercased())
                .font(.system(size: 12, weight: .heavy, design: .rounded))
                .foregroundStyle(Color.cpAccent)
                .tracking(1.2)

            VStack { Divider().background(Color.cpAccent.opacity(0.2)) }

            if let trailing {
                trailing()
            }
        }
    }
}

// MARK: - Pulsing Status Dot

struct PulsingDot: View {
    let color: Color
    var isAnimating: Bool = true

    @State private var isPulsing = false

    var body: some View {
        ZStack {
            if isAnimating {
                Circle()
                    .fill(color.opacity(0.3))
                    .frame(width: 16, height: 16)
                    .scaleEffect(isPulsing ? 2.0 : 1.0)
                    .opacity(isPulsing ? 0 : 0.6)
            }
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            guard isAnimating else { return }
            withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: false)) {
                isPulsing = true
            }
        }
    }
}

// MARK: - Haptics

enum CPHaptics {
    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}
