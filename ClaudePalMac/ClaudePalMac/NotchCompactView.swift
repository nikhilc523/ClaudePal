import SwiftUI
import ClaudePalMacCore

/// Compact notch pill: terminal mascot + model name + pending badge.
/// Continuously dances while pending decisions exist — stops when all resolved.
struct NotchCompactView: View {
    @ObservedObject var appState: AppState

    @State private var wiggleAngle: Double = 0
    @State private var bounceScale: CGFloat = 1.0
    @State private var glowOpacity: Double = 0
    @State private var isDancing = false

    var body: some View {
        HStack(spacing: 4) {
            // Mascot with glow
            ZStack {
                if glowOpacity > 0 {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.cpAccent.opacity(glowOpacity * 0.3))
                        .frame(width: 28, height: 28)
                        .blur(radius: 4)
                }
                TerminalMascot(size: 20, animated: true)
            }
            .rotationEffect(.degrees(wiggleAngle))
            .scaleEffect(bounceScale)

            // Model name (if detected)
            if let model = appState.currentModel {
                Text(model.friendlyName)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.cpTextSecondary)
                    .lineLimit(1)

                if model.isThinking {
                    Image(systemName: "brain")
                        .font(.system(size: 7))
                        .foregroundStyle(Color.cpAccent.opacity(0.7))
                }
            }

            // Service status dot
            if let status = appState.serviceStatus, !status.isOperational {
                Circle()
                    .fill(status.isCritical ? Color.cpDeny : Color.cpWarning)
                    .frame(width: 5, height: 5)
            }

            // Pending badge
            if appState.pendingCount > 0 {
                Text("|\u{2009}\(appState.pendingCount)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.cpWarning)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onChange(of: appState.pendingCount) { oldVal, newVal in
            if newVal > 0 && !isDancing {
                startDanceLoop()
            } else if newVal == 0 {
                stopDance()
            }
        }
        .onChange(of: appState.danceTrigger) {
            if !isDancing && appState.pendingCount > 0 {
                startDanceLoop()
            }
        }
    }

    private func startDanceLoop() {
        isDancing = true
        withAnimation(.easeIn(duration: 0.2)) { glowOpacity = 1 }
        danceOnce()
    }

    private func stopDance() {
        isDancing = false
        withAnimation(.easeOut(duration: 0.3)) {
            wiggleAngle = 0
            bounceScale = 1.0
            glowOpacity = 0
        }
    }

    private func danceOnce() {
        guard isDancing else { return }

        let steps: [(Double, CGFloat, Double)] = [
            (-10, 1.12, 0.08),
            (8, 1.08, 0.08),
            (-6, 1.06, 0.08),
            (4, 1.04, 0.08),
            (-2, 1.02, 0.08),
            (0, 1.0, 0.1),
        ]

        var delay: Double = 0
        for (angle, scale, dur) in steps {
            delay += dur
            let d = delay
            DispatchQueue.main.asyncAfter(deadline: .now() + d) {
                guard isDancing else { return }
                withAnimation(.easeInOut(duration: dur)) {
                    wiggleAngle = angle
                    bounceScale = scale
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay + 1.5) {
            guard isDancing, appState.pendingCount > 0 else {
                stopDance()
                return
            }
            danceOnce()
        }
    }
}
