import AppKit
import Observation

/// The last dictated text, kept only in memory so it can be pasted again.
/// It expires after `lifetime` and is dropped when the Mac locks or sleeps.
@MainActor
@Observable
final class DictationLastText {
    static let lifetime: TimeInterval = 15 * 60

    private var text: String?
    /// The clean text a polished or translated dictation started from, under the same lifetime.
    private var alternate: String?
    /// True when that text is the untranslated original rather than the unpolished one.
    private(set) var alternateIsOriginal = false
    private var storedAt: Date?
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private let waitForExpiry: @MainActor (Duration) async -> Void
    @ObservationIgnored private var expiry: Task<Void, Never>?

    var hasStoredText: Bool { text != nil }
    /// Runs on every clear, so the words can leave wherever else they are held.
    @ObservationIgnored var onClear: (() -> Void)?
    /// System sleep ends capture; display sleep and ordinary expiry only forget Paste last.
    @ObservationIgnored var onSystemSleep: (() -> Void)?

    init(
        now: @escaping () -> Date = Date.init, observesSystem: Bool = true,
        waitForExpiry: @escaping @MainActor (Duration) async -> Void = { try? await Task.sleep(for: $0) },
        workspaceNotifications: NotificationCenter? = nil,
        distributedNotifications: NotificationCenter? = nil
    ) {
        self.now = now
        self.waitForExpiry = waitForExpiry
        guard observesSystem else { return }
        let workspace = workspaceNotifications ?? NSWorkspace.shared.notificationCenter
        let distributed = distributedNotifications ?? DistributedNotificationCenter.default()
        let events: [(NotificationCenter, Notification.Name)] = [
            (workspace, NSWorkspace.willSleepNotification),
            (workspace, NSWorkspace.screensDidSleepNotification),
            (workspace, NSWorkspace.sessionDidResignActiveNotification),
            (distributed, Notification.Name("com.apple.screenIsLocked"))
        ]
        for (center, name) in events {
            let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWorkspace.willSleepNotification { self?.onSystemSleep?() }
                    self?.clear()
                }
            }
            observers.append(token)
        }
    }

    /// Read-only, so a view can ask without mutating state while it renders.
    var current: String? {
        guard let text, let storedAt, now().timeIntervalSince(storedAt) < Self.lifetime else { return nil }
        return text
    }

    var currentAlternate: String? { current == nil ? nil : alternate }

    /// The current text, dropping an expired one so its menu action disappears.
    func takeCurrent() -> String? {
        if current == nil, text != nil { clear() }
        return current
    }

    func takeCurrentAlternate() -> String? {
        if current == nil, text != nil { clear() }
        return currentAlternate
    }

    func remember(_ value: String, alternate: String? = nil, isOriginal: Bool = false) {
        text = value
        self.alternate = alternate == value ? nil : alternate
        alternateIsOriginal = self.alternate != nil && isOriginal
        storedAt = now()
        expiry?.cancel()
        // Expired text leaves memory on time, whether or not anything asks for it.
        expiry = Task { [weak self, waitForExpiry] in
            await waitForExpiry(.seconds(Self.lifetime))
            guard !Task.isCancelled else { return }
            self?.clear()
        }
    }

    func clear() {
        expiry?.cancel()
        expiry = nil
        text = nil
        alternate = nil
        alternateIsOriginal = false
        storedAt = nil
        onClear?()
    }
}
