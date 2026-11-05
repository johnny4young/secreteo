import DictationKit
import Foundation
import MicCapture
import SwiftUI

/// What a dictation does and how it starts, shown once dictation is on.
struct DictationSettingsControls: View {
    let dictation: DictationFeature
    @State private var microphones: [AudioInputDevice] = []

    var body: some View {
        Section("Triggers") {
            MouseButtonRecorder(
                button: dictation.mouseButton,
                onRecord: { dictation.recordMouseButton($0) })
            modifierKeyControls
        }
        Section("While Dictating") {
            Toggle("Play Start and Stop Sounds", isOn: dictation.preference(
                DictationSoundCue.defaultsKey, default: false))
                .accessibilityIdentifier("settings-dictation-sounds")
            Toggle("Show Only a Small Indicator", isOn: dictation.preference(
                DictationCompactIndicator.defaultsKey, default: false))
                .accessibilityIdentifier("settings-dictation-compact")
            Toggle("Skip Dictations Without Speech", isOn: dictation.preference(
                DictationSpeechGate.defaultsKey, default: DictationSpeechGate.enabledByDefault))
                .accessibilityIdentifier("settings-dictation-speech-gate")
            autoStopControls
            Toggle("Correct the Last Dictation by Voice", isOn: dictation.preference(
                DictationCorrections.defaultsKey, default: false))
                .help(L10n.text("Start a dictation with “change Friday to Monday”, “delete Friday” or “scratch that”."))
                .accessibilityIdentifier("settings-dictation-corrections")
            Toggle("Match Capitalization to the Cursor", isOn: dictation.preference(
                DictationCaretCase.defaultsKey, default: false))
                .accessibilityIdentifier("settings-dictation-caret-case")
        }
        Section("Language and Microphone") {
            Picker("Language", selection: dictation.preference(DictationController.languageKey, default: "auto")) {
                Text("Automatic").tag("auto")
                Text("Spanish").tag("es")
                Text("English").tag("en")
            }
            .accessibilityIdentifier("settings-dictation-language")
            microphonePicker
        }
        Section("Text") {
            let mode = dictation.textMode
            Picker("Text Mode", selection: dictation.textModeBinding) {
                Text("Literal").tag(DictationTextMode.literal)
                Text("Clean").tag(DictationTextMode.clean)
            }
            .accessibilityIdentifier("settings-dictation-text-mode")
            Toggle("Filter Out Filler Words", isOn: dictation.preference(
                DictationController.fillerFilterKey, default: true))
                .disabled(mode == .literal)
                .accessibilityIdentifier("settings-dictation-filler")
            DictationDictionaryEditor(stored: dictation.preference(DictationController.replacementsKey, default: ""))
                .disabled(mode == .literal)
        }
    }

    @ViewBuilder private var modifierKeyControls: some View {
        let key = dictation.preference(ModifierKeySetting.defaultsKey, default: ModifierKeySetting.off.rawValue)
        Picker("Hold a Key to Dictate", selection: Binding(
            get: { key.wrappedValue },
            set: {
                key.wrappedValue = $0
                dictation.triggersChanged(promptIfNeeded: true)
            })) {
            Text("Off").tag(ModifierKeySetting.off.rawValue)
            Text("Fn (🌐)").tag(ModifierKeySetting.function.rawValue)
            Text("Right Option").tag(ModifierKeySetting.rightOption.rawValue)
            Text("Right Command").tag(ModifierKeySetting.rightCommand.rawValue)
        }
        .accessibilityIdentifier("settings-dictation-modifier-key")
        if key.wrappedValue != ModifierKeySetting.off.rawValue, dictation.controller.modifierTrigger.unavailable {
            Text("Holding a key needs Accessibility permission.")
                .foregroundStyle(.red)
                .accessibilityIdentifier("settings-dictation-modifier-unavailable")
        }
        if key.wrappedValue == ModifierKeySetting.function.rawValue {
            Text("So macOS doesn't also react, set “Press 🌐 key to” to “Do Nothing” in System Settings › Keyboard.")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("settings-dictation-modifier-fn-note")
        }
    }

    @ViewBuilder private var autoStopControls: some View {
        let autoStops = dictation.preference(DictationAutoStop.defaultsKey, default: false)
        Toggle("Stop After a Pause", isOn: autoStops)
            .accessibilityIdentifier("settings-dictation-auto-stop")
        if autoStops.wrappedValue {
            Picker("Pause Length", selection: dictation.preference(
                DictationAutoStop.pauseKey, default: DictationAutoStop.defaultPause)) {
                ForEach(DictationAutoStop.pauses, id: \.self) { seconds in
                    Text(L10n.format("%.1f seconds", seconds)).tag(seconds)
                }
            }
            .accessibilityIdentifier("settings-dictation-auto-stop-pause")
        }
    }

    private var microphonePicker: some View {
        let selection = dictation.preference(
            MicrophoneInputSelection.preferenceKey, default: MicrophoneInputSelection.systemDefault)
        return Picker("Microphone", selection: selection) {
            Text("System Default").tag(MicrophoneInputSelection.systemDefault)
            ForEach(microphones) { device in
                Text(device.name).tag(device.uid)
            }
            if selection.wrappedValue != MicrophoneInputSelection.systemDefault,
               !microphones.contains(where: { $0.uid == selection.wrappedValue }) {
                Text("Unavailable — Using System Default").tag(selection.wrappedValue)
            }
        }
        .accessibilityIdentifier("settings-dictation-microphone-device")
        .task {
            microphones = await Task.detached(priority: .utility) {
                (try? AudioDeviceCatalog.inputDevices()) ?? []
            }.value
        }
    }
}
