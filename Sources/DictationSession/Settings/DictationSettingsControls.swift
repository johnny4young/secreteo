import AppKit
import DictationKit
import Foundation
import MicCapture
import SwiftUI

/// How a dictation starts, what hears it and what shows meanwhile. Off, only the shortcut shows.
struct DictationSettingsControls: View {
    let dictation: DictationFeature
    @State private var microphones: [AudioInputDevice] = []

    var body: some View {
        SettingsEyebrow(Text("Triggers"))
        SettingsCard {
            if dictation.isEnabled { modifierKeyControls }
            DictationShortcutSettings(
                shortcut: dictation.controller.shortcut,
                isUnavailable: dictation.shortcutIsUnavailable,
                record: { dictation.recordShortcut($0) },
                recordingChanged: { dictation.shortcutRecording($0) },
                retry: { dictation.triggersChanged() })
            if dictation.isEnabled {
                SettingsSwitch(
                    Text("Paste the Last Dictation"), identifier: "settings-dictation-paste-last-hotkey",
                    shortcut: PasteLastShortcut.setting.label, isOn: dictation.pasteLastShortcutBinding)
                if dictation.pasteLastShortcutIsUnavailable {
                    Text("Another shortcut already uses ⌃⌥⌘V.")
                        .foregroundStyle(SecreteoDesign.notSent)
                        .accessibilityIdentifier("settings-dictation-paste-last-taken")
                }
                MouseButtonRecorder(
                    button: dictation.mouseButton,
                    onRecord: { dictation.recordMouseButton($0) })
                autoStopControls
            }
        }
        if dictation.isEnabled { whileOn }
    }

    @ViewBuilder private var whileOn: some View {
        SettingsEyebrow(Text("Speech"))
        SettingsCard {
            SettingsRow(Text("Speech Engine")) {
                SettingsSegments(
                    identifier: "settings-dictation-engine", label: Text("Speech Engine"),
                    selection: dictation.speechEngineBinding,
                    options: [
                        .init(value: LiveSpeechSelection.parakeet, title: Text("Parakeet"), suffix: "parakeet"),
                        .init(value: .parakeetUltra, title: Text("Parakeet Ultra"), suffix: "ultra"),
                        .init(value: .appleSpeech, title: Text("Apple Speech"), suffix: "apple")
                    ])
            }
            .task(id: dictation.speechEngine) { await dictation.refreshUltra() }
            if dictation.speechEngine == .parakeetUltra, dictation.environment.models != nil {
                ultraRow
            }
            SettingsRow(Text("Language")) {
                Picker(selection: dictation.dictationLanguageBinding) {
                    if dictation.speechEngine != .appleSpeech {
                        Text("Automatic").tag("auto")
                    }
                    Text("Spanish").tag("es")
                    Text("English").tag("en")
                } label: {
                    Text("Language")
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("settings-dictation-language")
            }
            SettingsRow(Text("Microphone")) {
                DictationMicrophoneMeter(controller: dictation.controller)
                microphonePicker
            }
            SettingsSwitch(
                Text("Skip Dictations Without Speech"), identifier: "settings-dictation-speech-gate",
                isOn: dictation.preference(
                    DictationSpeechGate.defaultsKey, default: DictationSpeechGate.enabledByDefault))
        }
        SettingsEyebrow(Text("While Dictating"))
        SettingsCard {
            let isCompact = dictation.preference(DictationCompactIndicator.defaultsKey, default: false)
            DictationIndicatorChoice(isCompact: isCompact)
                .padding(.vertical, 3)
            DictationIndicatorOption(
                Text("Show Elapsed Time"), identifier: "settings-dictation-compact-elapsed",
                isOn: dictation.preference(DictationCompactIndicator.elapsedTimeKey, default: false),
                isAvailable: isCompact.wrappedValue
            ) {
                DictationAsideBody(face: .listening, fixedOpenness: 0.5, time: "0:07", bead: true, ring: false)
            }
            DictationIndicatorOption(
                Text("Show a Backdrop"), identifier: "settings-dictation-compact-backdrop",
                isOn: dictation.preference(DictationCompactIndicator.backdropKey, default: false),
                isAvailable: isCompact.wrappedValue
            ) {
                DictationAsideBody(face: .listening, fixedOpenness: 0.5, bead: true)
            }
            SettingsSwitch(
                Text("Play Start and Stop Sounds"), identifier: "settings-dictation-sounds",
                isOn: dictation.preference(DictationSoundCue.defaultsKey, default: false))
        }
    }

    /// Until Ultra is downloaded, dictation keeps using Parakeet.
    @ViewBuilder private var ultraRow: some View {
        switch dictation.ultra.state {
        case .ready:
            EmptyView()
        case .downloading:
            HStack(spacing: 10) {
                Text("Downloading Parakeet Ultra…")
                    .foregroundStyle(SecreteoDesign.secondaryText)
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                ProgressView(value: dictation.ultra.fraction)
                    .frame(width: 160)
                    .accessibilityLabel(L10n.text("Downloading Parakeet Ultra…"))
                    .accessibilityIdentifier("settings-dictation-ultra-progress")
                if let fraction = dictation.ultra.fraction {
                    Text(verbatim: fraction.formatted(.percent.precision(.fractionLength(0))))
                        .monospacedDigit()
                        .foregroundStyle(SecreteoDesign.secondaryText)
                        .accessibilityHidden(true)
                }
            }
        case .missing, .failed:
            Button("Download Parakeet Ultra") { dictation.downloadUltra() }
                .accessibilityIdentifier("settings-dictation-ultra-download")
            if dictation.ultra.state == .failed {
                Text("The download failed.")
                    .foregroundStyle(SecreteoDesign.notSent)
                    .accessibilityIdentifier("settings-dictation-ultra-failed")
            }
        }
    }

    @ViewBuilder private var modifierKeyControls: some View {
        let key = dictation.preference(ModifierKeySetting.defaultsKey, default: ModifierKeySetting.standard.rawValue)
        let picker = Picker(selection: Binding(
            get: { key.wrappedValue },
            set: {
                key.wrappedValue = $0
                dictation.triggersChanged(promptIfNeeded: true)
            })) {
            Text("Off").tag(ModifierKeySetting.off.rawValue)
            Text("Fn (🌐)").tag(ModifierKeySetting.function.rawValue)
            Text("Right Option").tag(ModifierKeySetting.rightOption.rawValue)
            Text("Right Command").tag(ModifierKeySetting.rightCommand.rawValue)
        } label: {
            Text("Hold a Key to Dictate")
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("settings-dictation-modifier-key")
        SettingsRow(Text("Hold a Key to Dictate")) {
            // The strip is the first thing to go when the label needs the room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) {
                    DictationHoldKeyStrip(key: ModifierKeySetting(rawValue: key.wrappedValue) ?? .off)
                    picker
                }
                picker
            }
        }
        if key.wrappedValue != ModifierKeySetting.off.rawValue, dictation.controller.modifierTrigger.unavailable {
            Text("Holding a key needs Accessibility permission.")
                .foregroundStyle(SecreteoDesign.notSent)
                .accessibilityIdentifier("settings-dictation-modifier-unavailable")
        }
        if key.wrappedValue == ModifierKeySetting.function.rawValue, !dictation.fnKeyIsFree {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("So macOS doesn't also react, set “Press 🌐 key to” to “Do Nothing”.")
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("settings-dictation-modifier-fn-note")
                Spacer(minLength: 4)
                Button("Open Keyboard Settings") { dictation.openKeyboardSettings() }
                    .buttonStyle(SettingsLinkStyle())
                    .accessibilityIdentifier("settings-dictation-modifier-fn-settings")
            }
        }
    }

    private var autoStopControls: some View {
        let autoStops = dictation.preference(DictationAutoStop.defaultsKey, default: false)
        let pause = dictation.preference(DictationAutoStop.pauseKey, default: DictationAutoStop.defaultPause)
        return SettingsSwitch(
            Text("Stop After a Pause"), identifier: "settings-dictation-auto-stop", isOn: autoStops
        ) {
            DictationPauseDiagram()
            if autoStops.wrappedValue {
                // An unknown value stops at the default, so the picker says so.
                Picker(selection: Binding(
                    get: {
                        DictationAutoStop.pauses.contains(pause.wrappedValue)
                            ? pause.wrappedValue : DictationAutoStop.defaultPause
                    },
                    set: { pause.wrappedValue = $0 })) {
                    ForEach(DictationAutoStop.pauses, id: \.self) { seconds in
                        Text(L10n.format("%.1f seconds", seconds)).tag(seconds)
                    }
                } label: {
                    Text("Pause Length")
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityIdentifier("settings-dictation-auto-stop-pause")
            }
        }
    }

    private var microphonePicker: some View {
        let selection = dictation.preference(
            MicrophoneInputSelection.preferenceKey, default: MicrophoneInputSelection.systemDefault)
        return Picker(selection: selection) {
            Text("System Default").tag(MicrophoneInputSelection.systemDefault)
            ForEach(microphones) { device in
                Text(device.name).tag(device.uid)
            }
            if selection.wrappedValue != MicrophoneInputSelection.systemDefault,
               !microphones.contains(where: { $0.uid == selection.wrappedValue }) {
                Text("Unavailable — Using System Default").tag(selection.wrappedValue)
            }
        } label: {
            Text("Microphone")
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityIdentifier("settings-dictation-microphone-device")
        .task { await refreshMicrophones() }
        // The window is kept when closed, so a microphone plugged in since needs another look.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            Task { await refreshMicrophones() }
        }
    }

    private func refreshMicrophones() async {
        microphones = await Task.detached(priority: .utility) {
            (try? AudioDeviceCatalog.inputDevices()) ?? []
        }.value
    }
}
