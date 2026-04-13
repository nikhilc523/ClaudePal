import SwiftUI
import AppKit
import ClaudePalMacCore

/// Sound settings popover — configure sounds for each event type.
struct SoundSettingsView: View {
    @ObservedObject var appState: AppState

    private let availableSounds = SoundPreferences.availableSystemSounds()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color.cpAccent)
                Text("Sound Settings")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }

            // Mute toggle
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
                Divider()

                ForEach(SoundEventType.allCases, id: \.self) { eventType in
                    soundRow(for: eventType)
                }
            }
        }
        .padding(12)
        .frame(width: 240)
    }

    @ViewBuilder
    private func soundRow(for eventType: SoundEventType) -> some View {
        HStack(spacing: 6) {
            Text(eventLabel(eventType))
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(Color.cpTextSecondary)
                .frame(width: 60, alignment: .leading)

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
