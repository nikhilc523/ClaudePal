import SwiftUI
import ClaudePalMacCore

/// Top-level SwiftUI view embedded in the notch panel's NSHostingView.
struct NotchPanelRootView: View {
    @ObservedObject var appState: AppState
    var mode: NotchPanelMode
    var onExpand: () -> Void
    var onCollapse: () -> Void
    var onApprove: (PendingDecision) -> Void
    var onDeny: (PendingDecision) -> Void

    var body: some View {
        switch mode {
        case .hidden:
            Color.clear.frame(width: 0, height: 0)

        case .compact:
            NotchCompactView(appState: appState)
                .onTapGesture { onExpand() }

        case .attention:
            AttentionView(appState: appState)
                .contentShape(Rectangle())
                .onTapGesture { onExpand() }

        case .expanded:
            NotchExpandedView(
                appState: appState,
                onApprove: onApprove,
                onDeny: onDeny,
                onCollapse: onCollapse
            )
            .clipShape(expandedShape)
            .background(expandedShape.fill(Color.cpBackground))
            .overlay(
                expandedShape
                    .stroke(
                        LinearGradient(
                            colors: [Color.white.opacity(0.08), Color.white.opacity(0.02)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: Color.cpAccent.opacity(0.08), radius: 20, y: 8)
        }
    }

    private var expandedShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
    }
}

// MARK: - Attention View (Face ID-style premium pop-out)

struct AttentionView: View {
    @ObservedObject var appState: AppState

    // Glow animations
    @State private var outerGlow = false
    @State private var innerGlow = false
    @State private var ringRotation: Double = 0

    // Eye scan animation
    @State private var eyeOffset: CGFloat = 0

    // Scale entrance
    @State private var mascotScale: CGFloat = 0.3
    @State private var contentOpacity: Double = 0

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                // Layer 1: Outer rotating glow ring
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                Color.cpAccent.opacity(0.0),
                                Color.cpAccent.opacity(0.2),
                                Color.cpSecondary.opacity(0.15),
                                Color.cpAccent.opacity(0.0),
                            ],
                            center: .center
                        ),
                        lineWidth: 2
                    )
                    .frame(width: 180, height: 180)
                    .rotationEffect(.degrees(ringRotation))
                    .blur(radius: 1)

                // Layer 2: Outer pulsing glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cpAccent.opacity(outerGlow ? 0.12 : 0.03),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 40,
                            endRadius: 100
                        )
                    )
                    .frame(width: 200, height: 200)

                // Layer 3: Inner glow
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.cpAccent.opacity(innerGlow ? 0.2 : 0.05),
                                Color.cpSecondary.opacity(0.05),
                                Color.clear,
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 70
                        )
                    )
                    .frame(width: 160, height: 160)

                // Layer 4: The mascot — BIG with scanning eyes
                AttentionMascot(eyeOffset: eyeOffset)
                    .scaleEffect(mascotScale)
            }

            // Tool info — fades in
            VStack(spacing: 6) {
                if let first = appState.pendingDecisions.first {
                    HStack(spacing: 4) {
                        Image(systemName: first.isDestructive ? "exclamationmark.triangle.fill" : "terminal.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(first.isDestructive ? Color.cpDeny : Color.cpAccent)
                        Text(first.toolName ?? "Unknown")
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(Color.cpTextPrimary)
                    }

                    if let input = first.toolInput {
                        Text(formatInput(input))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(Color.cpTextSecondary)
                            .lineLimit(1)
                    }
                }

                Text("Tap to review")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Color.cpAccent.opacity(0.6))
                    .padding(.top, 2)
            }
            .opacity(contentOpacity)
        }
        .frame(width: 260, height: 300)
        .onAppear {
            startAnimations()
        }
    }

    private func startAnimations() {
        // Entrance: scale up with spring
        withAnimation(.spring(response: 0.6, dampingFraction: 0.7, blendDuration: 0)) {
            mascotScale = 1.0
        }

        // Text fade in
        withAnimation(.easeOut(duration: 0.4).delay(0.3)) {
            contentOpacity = 1.0
        }

        // Continuous: outer glow pulse
        withAnimation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true)) {
            outerGlow = true
        }

        // Continuous: inner glow pulse (offset phase)
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true).delay(0.5)) {
            innerGlow = true
        }

        // Continuous: ring rotation
        withAnimation(.linear(duration: 4.0).repeatForever(autoreverses: false)) {
            ringRotation = 360
        }

        // Eye scanning: look left, center, right, center — loop
        startEyeScan()
    }

    private func formatInput(_ raw: String) -> String {
        if let data = raw.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let cmd = json["command"] as? String { return "$ \(cmd)" }
            if let fp = json["file_path"] as? String { return fp }
        }
        return String(raw.prefix(60))
    }

    private func startEyeScan() {
        Task {
            while !Task.isCancelled {
                // Look left
                withAnimation(.easeInOut(duration: 0.4)) { eyeOffset = -3 }
                try? await Task.sleep(nanoseconds: 600_000_000)
                // Look center
                withAnimation(.easeInOut(duration: 0.3)) { eyeOffset = 0 }
                try? await Task.sleep(nanoseconds: 400_000_000)
                // Look right
                withAnimation(.easeInOut(duration: 0.4)) { eyeOffset = 3 }
                try? await Task.sleep(nanoseconds: 600_000_000)
                // Look center
                withAnimation(.easeInOut(duration: 0.3)) { eyeOffset = 0 }
                try? await Task.sleep(nanoseconds: 800_000_000)
            }
        }
    }
}

// MARK: - Attention Mascot (large, with animated scanning eyes)

struct AttentionMascot: View {
    var eyeOffset: CGFloat

    private let size: CGFloat = 120

    var body: some View {
        ZStack {
            // Terminal body
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.14, blue: 0.18),
                            Color(red: 0.08, green: 0.08, blue: 0.12),
                        ],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)

            // Border glow
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.cpAccent.opacity(0.5), Color.cpSecondary.opacity(0.25)],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )
                .frame(width: size, height: size)

            // Traffic light dots
            HStack(spacing: 7) {
                Circle().fill(Color.cpDeny.opacity(0.9)).frame(width: 8, height: 8)
                Circle().fill(Color.cpWarning.opacity(0.9)).frame(width: 8, height: 8)
                Circle().fill(Color.cpApprove.opacity(0.9)).frame(width: 8, height: 8)
            }
            .offset(y: -38)

            // Face with scanning eyes
            HStack(spacing: 3) {
                // Left eye >
                Text(">")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cpAccent)

                // Mouth _
                Text("_")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cpAccent.opacity(0.5))
                    .offset(y: 5)

                // Right eye <
                Text("<")
                    .font(.system(size: 32, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cpAccent)
            }
            .offset(x: eyeOffset, y: 8)
        }
        .shadow(color: Color.cpAccent.opacity(0.25), radius: 20, y: 6)
    }
}

/// Panel display mode.
enum NotchPanelMode: Equatable {
    case hidden
    case compact
    case attention
    case expanded
}
