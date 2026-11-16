import AppKit
import DictationSession
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
            // After the layout pass that measured it, so the frame never changes inside one.
            let view = SettingsView(model: model) { [weak self] height in
                DispatchQueue.main.async { self?.fit(height: height) }
            }
            let hosting = NSHostingController(rootView: view)
            // The window follows the tab's height itself, so the top edge stays where it is.
            hosting.sizingOptions = []
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Settings")
            created.styleMask = [.titled, .closable, .fullSizeContentView]
            created.titleVisibility = .hidden
            created.titlebarAppearsTransparent = true
            created.setContentSize(NSSize(width: SettingsMetrics.width, height: 560))
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

    private func fit(height: CGFloat) {
        guard let window else { return }
        let frame = Self.fitted(window.frame, height: height, in: window.screen?.visibleFrame)
        guard frame != window.frame else { return }
        window.setFrame(frame, display: true)
    }

    /// The top edge stays put while the window fits on the screen. Otherwise it moves up, and a tab
    /// taller than the screen gets the screen's height, so it scrolls instead of hiding rows.
    nonisolated static func fitted(_ frame: NSRect, height: CGFloat, in visible: NSRect?) -> NSRect {
        let target = min(height, visible?.height ?? height)
        var fitted = NSRect(x: frame.minX, y: frame.maxY - target, width: SettingsMetrics.width, height: target)
        guard let visible else { return fitted }
        fitted.origin.y = min(max(fitted.minY, visible.minY), visible.maxY - target)
        return fitted
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
