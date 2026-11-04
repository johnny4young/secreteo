import AppKit

/// Dictated words go to whichever app has focus, and opening the menu took it.
/// So a menu action first gives focus back to the app the user was in.
@MainActor
final class MenuFocusReturn {
    struct System {
        var ownProcess: pid_t
        var frontmost: @MainActor () -> pid_t?
        var activate: @MainActor (pid_t) -> Void
        var pause: @Sendable () async -> Void

        static let live = System(
            ownProcess: ProcessInfo.processInfo.processIdentifier,
            frontmost: { NSWorkspace.shared.frontmostApplication?.processIdentifier },
            activate: { process in
                guard let app = NSRunningApplication(processIdentifier: process) else { return }
                NSApp.yieldActivation(to: app)
                app.activate(from: .current)
            },
            pause: { try? await Task.sleep(for: .milliseconds(20)) })
    }

    /// About half a second. An action the user asked for still runs if the other app never answers.
    private static let looks = 25
    private let system: System
    private var target: pid_t?

    init(system: System = .live) {
        self.system = system
    }

    /// Call before this app activates itself.
    func remember() {
        aim(at: system.frontmost())
    }

    func aim(at process: pid_t?) {
        target = process == system.ownProcess ? nil : process
    }

    func run(_ action: @escaping @MainActor () -> Void) {
        guard let target else {
            action()
            return
        }
        self.target = nil
        system.activate(target)
        Task {
            for _ in 0..<Self.looks where system.frontmost() != target {
                await system.pause()
            }
            action()
        }
    }
}
