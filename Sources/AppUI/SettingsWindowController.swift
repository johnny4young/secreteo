import AppKit
import SwiftUI

/// A plain window rather than a SwiftUI `Settings` scene, which an agent app with no
/// main menu cannot open reliably.
@MainActor
public final class SettingsWindowController {
    private let model: AppModel
    private var window: NSWindow?

    public init(model: AppModel) {
        self.model = model
    }

    public func show() {
        if window == nil {
            let created = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: model)))
            created.title = String(localized: "Settings")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.identifier = NSUserInterfaceItemIdentifier("settings-window")
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        // An agent app needs both, or the window can open behind the active app.
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }
}
