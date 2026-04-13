import SwiftUI
import AppKit
import ClaudePalMacCore

/// Settings popover — sound config + session cookie for usage tracking.
struct SoundSettingsView: View {
    @ObservedObject var appState: AppState
    @State private var cookieInput = ""
    @State private var showCookieField = false

    private let availableSounds = SoundPreferences.availableSystemSounds()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // MARK: - Usage / Cookie

            HStack {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.cpAccent)
                Text("Usage Tracking")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }

            if appState.hasSessionCookie {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.cpApprove)
                    Text("Session cookie active")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.cpTextSecondary)
                    Spacer()
                    Button("Clear") {
                        appState.clearSessionCookie()
                    }
                    .font(.system(size: 9))
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.cpDeny)
                }
            } else {
                if showCookieField {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paste your sessionKey from claude.ai cookies:")
                            .font(.system(size: 8))
                            .foregroundStyle(Color.cpTextTertiary)
                        HStack(spacing: 4) {
                            TextField("sk-ant-...", text: $cookieInput)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(size: 9, design: .monospaced))
                                .controlSize(.small)
                            Button("Save") {
                                appState.setSessionCookie(cookieInput)
                                cookieInput = ""
                                showCookieField = false
                            }
                            .font(.system(size: 9, weight: .medium))
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .tint(Color.cpAccent)
                            .disabled(cookieInput.isEmpty)
                        }
                    }
                } else {
                    Button {
                        showCookieField = true
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 8))
                            Text("Add Session Cookie")
                                .font(.system(size: 9, weight: .medium))
                        }
                        .foregroundStyle(Color.cpAccent)
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider()

            // MARK: - Sound Settings

            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.cpAccent)
                Text("Sounds")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }

            Toggle(isOn: Binding(
                get: { appState.soundPreferences.isMuted },
                set: { muted in
                    var prefs = appState.soundPreferences
                    prefs.isMuted = muted
                    appState.updateSoundPreferences(prefs)
                }
            )) {
                Text("Mute all sounds")
                    .font(.system(size: 10))
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            if !appState.soundPreferences.isMuted {
                ForEach(SoundEventType.allCases, id: \.self) { eventType in
                    soundRow(for: eventType)
                }
            }
        }
        .padding(12)
        .frame(width: 260)
    }

    @ViewBuilder
    private func soundRow(for eventType: SoundEventType) -> some View {
        HStack(spacing: 6) {
            Text(eventLabel(eventType))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.cpTextSecondary)
                .frame(width: 50, alignment: .leading)

            Picker("", selection: Binding(
                get: { appState.soundPreferences.soundName(for: eventType) },
                set: { name in
                    var prefs = appState.soundPreferences
                    prefs.sounds[eventType] = name
                    appState.updateSoundPreferences(prefs)
                }
            )) {
                ForEach(availableSounds, id: \.self) { name in
                    Text(name).tag(name)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(maxWidth: .infinity)

            Button {
                let name = appState.soundPreferences.soundName(for: eventType)
                NSSound(named: NSSound.Name(name))?.play()
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(Color.cpAccent)
            }
            .buttonStyle(.plain)
        }
    }

    private func eventLabel(_ type: SoundEventType) -> String {
        switch type {
        case .permissionPrompt: "Prompt"
        case .taskCompletion: "Done"
        case .notification: "Notify"
        }
    }
}
