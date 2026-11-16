import AppKit
import DictationSession
import SwiftUI

/// The dictation history in its own window, opened from the menu.
@MainActor
final class HistoryWindowController {
    private let dictation: DictationFeature
    private var window: NSWindow?

    init(dictation: DictationFeature) {
        self.dictation = dictation
    }

    func show() {
        if window == nil {
            let created = NSWindow(
                contentViewController: NSHostingController(
                    rootView: DictationHistoryView(dictation: dictation).tint(SecreteoDesign.accent)))
            created.title = String(localized: "Dictation History")
            created.styleMask = [.titled, .closable, .resizable]
            // The page has its own heading; the title stays for the Window menu and VoiceOver.
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.backgroundColor = SecreteoPalette.window.nsColor
            created.setContentSize(NSSize(width: 900, height: 720))
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        // An agent app needs both, or the window can open behind the active app.
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}
