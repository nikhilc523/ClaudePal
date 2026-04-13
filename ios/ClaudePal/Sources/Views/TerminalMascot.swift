import SwiftUI

/// A cute terminal mascot — a rounded terminal window with `>_<` as the face.
/// The `>` and `<` are the squinting eyes, `_` is the mouth.
struct TerminalMascot: View {
    var size: CGFloat = 48
    var animated: Bool = true

    @State private var blinkPhase = false

    private var scale: CGFloat { size / 48 }

    var body: some View {
        ZStack {
            // Terminal window body
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.14, blue: 0.18),
                            Color(red: 0.10, green: 0.10, blue: 0.14),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: size, height: size)

            // Terminal window border glow
            RoundedRectangle(cornerRadius: 12 * scale, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.cpAccent.opacity(0.4), Color.cpSecondary.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1.5 * scale
                )
                .frame(width: size, height: size)

            // Title bar dots (centered)
            HStack(spacing: 3 * scale) {
                Circle().fill(Color.cpDeny.opacity(0.8)).frame(width: 4 * scale, height: 4 * scale)
                Circle().fill(Color.cpWarning.opacity(0.8)).frame(width: 4 * scale, height: 4 * scale)
                Circle().fill(Color.cpApprove.opacity(0.8)).frame(width: 4 * scale, height: 4 * scale)
            }
            .offset(y: -16 * scale)

            // The face: >_<
            HStack(spacing: 1 * scale) {
                // Left eye: >
                Text(blinkPhase ? "—" : ">")
                    .font(.system(size: 13 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cpAccent)

                // Mouth: _
                Text("_")
                    .font(.system(size: 13 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cpAccent.opacity(0.6))
                    .offset(y: 2 * scale)

                // Right eye: <
                Text(blinkPhase ? "—" : "<")
                    .font(.system(size: 13 * scale, weight: .black, design: .monospaced))
                    .foregroundStyle(Color.cpAccent)
            }
            .offset(y: 3 * scale)
        }
        .shadow(color: Color.cpAccent.opacity(0.15), radius: 8 * scale, y: 2 * scale)
        .onAppear {
            guard animated else { return }
            startBlinking()
        }
    }

    private func startBlinking() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64.random(in: 2_000_000_000...5_000_000_000))
                withAnimation(.easeInOut(duration: 0.12)) { blinkPhase = true }
                try? await Task.sleep(nanoseconds: 150_000_000)
                withAnimation(.easeInOut(duration: 0.12)) { blinkPhase = false }
            }
        }
    }
}

/// Larger version for app icon rendering / about screens.
struct TerminalMascotLarge: View {
    var body: some View {
        ZStack {
            // Background
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.08, green: 0.08, blue: 0.12),
                            Color(red: 0.05, green: 0.05, blue: 0.08),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Outer glow ring
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.cpAccent.opacity(0.5), Color.cpSecondary.opacity(0.3), Color.cpAccent.opacity(0.2)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 2
                )

            VStack(spacing: 6) {
                // Title bar dots (centered)
                HStack(spacing: 5) {
                    Circle().fill(Color.cpDeny).frame(width: 8, height: 8)
                    Circle().fill(Color.cpWarning).frame(width: 8, height: 8)
                    Circle().fill(Color.cpApprove).frame(width: 8, height: 8)
                }
                .padding(.top, 14)

                Spacer()

                // Face
                HStack(spacing: 2) {
                    Text(">")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.cpAccent)
                    Text("_")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.cpAccent.opacity(0.5))
                        .offset(y: 4)
                    Text("<")
                        .font(.system(size: 32, weight: .black, design: .monospaced))
                        .foregroundStyle(Color.cpAccent)
                }

                Spacer()

                // Prompt line
                HStack(spacing: 4) {
                    Text("$")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.cpApprove.opacity(0.6))
                    RoundedRectangle(cornerRadius: 1)
                        .fill(Color.cpAccent.opacity(0.4))
                        .frame(width: 8, height: 14)
                }
                .padding(.bottom, 14)
            }
        }
        .frame(width: 120, height: 120)
        .shadow(color: Color.cpAccent.opacity(0.2), radius: 16, y: 4)
    }
}

#Preview {
    VStack(spacing: 40) {
        TerminalMascot(size: 52)
        TerminalMascotLarge()
    }
    .padding(40)
    .background(Color.cpBackground)
    .preferredColorScheme(.dark)
}
