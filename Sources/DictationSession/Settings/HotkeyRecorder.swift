import AppKit
import Carbon.HIToolbox
import SwiftUI

/// "Click, press your combo": a minimal hotkey recorder. While armed, a
/// LOCAL key monitor captures the next combination; Esc cancels.
struct HotkeyRecorder: View {
    @State private var recording = false
    @State private var monitor: Any?
    let setting: HotkeySetting
    let onRecord: (HotkeySetting) -> Void

    var body: some View {
        HStack {
            Text("Dictation Shortcut")
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(recording ? L10n.text("Press keys…") : setting.label)
                    .font(.body.monospaced())
                    .frame(minWidth: 90)
            }
            .accessibilityIdentifier("settings-dictation-hotkey-recorder")
        }
        .onDisappear(perform: stopRecording)
    }

    private func startRecording() {
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            defer { stopRecording() }
            guard event.keyCode != UInt16(kVK_Escape) else { return nil }
            guard let setting = HotkeySetting.from(event: event) else {
                NSSound.beep()  // combo without ⌘/⌥ would hijack typing
                return nil
            }
            onRecord(setting)
            return nil
        }
    }

    private func stopRecording() {
        recording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}
