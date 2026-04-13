import SwiftUI

// MARK: - Color Palette (macOS — matches iOS design system)

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

// MARK: - Gradients

enum CPGradient {
    static let cardBorder = LinearGradient(
        colors: [Color.white.opacity(0.10), Color.white.opacity(0.03)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let hero = LinearGradient(
        colors: [
            Color(red: 0.52, green: 0.32, blue: 0.18),
            Color(red: 0.40, green: 0.28, blue: 0.48),
            Color(red: 0.30, green: 0.24, blue: 0.56),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}
