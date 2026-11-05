import AppKit
import Carbon.HIToolbox
import SwiftUI

struct MouseButtonRecorder: View {
    @State private var recording = false
    @State private var monitors: [Any] = []
    let button: Int
    let onRecord: (Int) -> Void

    var body: some View {
        HStack {
            Text("Push-to-Talk Mouse Button")
            Spacer()
            Button {
                recording ? stopRecording() : startRecording()
            } label: {
                Text(currentLabel)
                    .font(.body.monospaced())
                    .frame(minWidth: 90)
            }
            .accessibilityIdentifier("settings-dictation-mouse-recorder")
            if button != MouseButtonSetting.off, !recording {
                Button {
                    onRecord(MouseButtonSetting.off)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.text("Remove the Push-to-Talk Mouse Button"))
                .accessibilityIdentifier("settings-dictation-mouse-clear")
            }
        }
        .onDisappear(perform: stopRecording)
    }

    private var currentLabel: String {
        if recording { return L10n.text("Click a mouse button…") }
        if button == MouseButtonSetting.off { return L10n.text("Off") }
        return MouseButtonSetting.label(for: button)
    }

    private func startRecording() {
        recording = true
        let mouse = NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { event in
            defer { stopRecording() }
            let candidate = event.buttonNumber
            guard MouseButtonSetting.isEligible(candidate) else {
                NSSound.beep()
                return nil
            }
            onRecord(candidate)
            return nil
        }
        let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == UInt16(kVK_Escape) else { return event }
            stopRecording()
            return nil
        }
        monitors = [mouse, keys].compactMap { $0 }
    }

    private func stopRecording() {
        recording = false
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors = []
    }
}
