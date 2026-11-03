import AppKit

/// Offers once to move the app to /Applications, then relaunches from there.
@MainActor
enum ApplicationMover {
    private static let declinedKey = "moveToApplicationsDeclined"

    /// Returns true when the app is relaunching and this process should quit.
    /// `releaseInstanceLock` runs first, or the new copy could find the lock held,
    /// quit, and leave no app running once this one ends.
    static func offerIfNeeded(releaseInstanceLock: () -> Void) -> Bool {
        let bundleURL = Bundle.main.bundleURL
        let defaults = UserDefaults.standard
        guard ApplicationLocation.shouldOfferMove(
            bundleURL: bundleURL, homeDirectory: FileManager.default.homeDirectoryForCurrentUser),
            !defaults.bool(forKey: declinedKey) else { return false }

        let alert = NSAlert()
        alert.messageText = String(localized: "Move Secreteo to Applications?")
        alert.informativeText = String(localized: "Open at Login and permissions need it there.")
        alert.addButton(withTitle: String(localized: "Move to Applications"))
        alert.addButton(withTitle: String(localized: "Not Now"))
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else {
            defaults.set(true, forKey: declinedKey)
            return false
        }

        let destination = URL(fileURLWithPath: "/Applications").appendingPathComponent(bundleURL.lastPathComponent)
        do {
            try install(bundleURL, at: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = String(localized: "Could not move Secreteo.")
            failure.runModal()
            return false
        }
        releaseInstanceLock()
        NSWorkspace.shared.openApplication(at: destination, configuration: .init())
        return true
    }

    /// Copies before touching anything, so a failed copy leaves the installed app in place,
    /// and only replaces an older copy of this app, never another app with the same name.
    private static func install(_ source: URL, at destination: URL) throws {
        let manager = FileManager.default
        let incoming = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(UUID().uuidString)-\(destination.lastPathComponent)")
        try manager.copyItem(at: source, to: incoming)
        do {
            if manager.fileExists(atPath: destination.path) {
                guard Bundle(url: destination)?.bundleIdentifier == Bundle.main.bundleIdentifier else {
                    throw CocoaError(.fileWriteFileExists)
                }
                try manager.trashItem(at: destination, resultingItemURL: nil)
            }
            try manager.moveItem(at: incoming, to: destination)
        } catch {
            try? manager.removeItem(at: incoming)
            throw error
        }
    }
}
