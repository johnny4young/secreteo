import AppKit
import SwiftUI

/// A plain window rather than a SwiftUI `Settings` scene, which an agent app with no
/// main menu cannot open reliably.
@MainActor
public final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?
    private var observers: [any NSObjectProtocol] = []

    public init(model: AppModel) {
        self.model = model
    }

    public func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            created.title = String(localized: "Settings")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            observe(created)
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        // The first text field would take focus and scroll the form down to itself.
        window?.makeFirstResponder(nil)
        // An agent app needs both, or the window can open behind the active app.
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private func observe(_ window: NSWindow) {
        let events: [(Notification.Name, @MainActor (SettingsWindowController) -> Void)] = [
            (NSWindow.didBecomeKeyNotification, { $0.model.dictation?.settingsWindowChanged(isKey: true) }),
            (NSWindow.didResignKeyNotification, { $0.model.dictation?.settingsWindowChanged(isKey: false) }),
            (NSWindow.willCloseNotification, { $0.model.dictation?.settingsWindowClosed() })
        ]
        observers = events.map { name, event in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if let self { event(self) }
                }
            }
        }
    }
}
