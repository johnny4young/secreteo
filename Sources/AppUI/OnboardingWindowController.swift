import AppKit
import DictationSession
import SwiftUI

/// Whether first-run setup is behind the user. A disposable launch never writes it.
struct FirstRunOnboardingRecord {
    static let key = "hasCompletedOnboarding"
    let defaults: UserDefaults
    let isDisposable: Bool

    var hasCompleted: Bool { defaults.bool(forKey: Self.key) }

    func markCompleted() {
        guard !isDisposable else { return }
        defaults.set(true, forKey: Self.key)
    }
}

/// Closing the window counts as finishing, because a user who closes it does not want it again.
@MainActor
final class OnboardingWindowController {
    private let dictation: DictationFeature
    private let onClose: @MainActor () -> Void
    private let practiceHolder = UUID()
    private var window: NSWindow?
    private var observers: [any NSObjectProtocol] = []
    private var isKey = false
    private var showsPractice = false

    init(dictation: DictationFeature, onClose: @escaping @MainActor () -> Void) {
        self.dictation = dictation
        self.onClose = onClose
    }

    func show() {
        if window == nil {
            let view = OnboardingView(
                dictation: dictation,
                practiceShown: { [weak self] in self?.practiceShown($0) },
                onFinish: { [weak self] in self?.window?.close() })
            let created = NSWindow(contentViewController: NSHostingController(rootView: view))
            created.title = String(localized: "Set Up Secreteo")
            created.styleMask = [.titled, .closable]
            created.isReleasedWhenClosed = false
            created.center()
            observe(created)
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        window?.makeFirstResponder(nil)
        // An agent app needs both, or the window can open behind the active app.
        NSApp.activate()
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    /// The window holds the field only on the practice step, or the shortcut would type into a hidden field.
    private func practiceShown(_ shown: Bool) {
        showsPractice = shown
        if shown {
            dictation.practiceWindowChanged(practiceHolder, isKey: isKey)
        } else {
            dictation.practiceWindowClosed(practiceHolder)
        }
    }

    private func keyChanged(_ key: Bool) {
        isKey = key
        if showsPractice { dictation.practiceWindowChanged(practiceHolder, isKey: key) }
    }

    private func closed() {
        practiceShown(false)
        onClose()
    }

    private func observe(_ window: NSWindow) {
        let events: [(Notification.Name, @MainActor (OnboardingWindowController) -> Void)] = [
            (NSWindow.didBecomeKeyNotification, { $0.keyChanged(true) }),
            (NSWindow.didResignKeyNotification, { $0.keyChanged(false) }),
            (NSWindow.willCloseNotification, { $0.closed() })
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
