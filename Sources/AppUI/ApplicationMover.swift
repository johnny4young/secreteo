import AppKit

/// Offers once to move the app to /Applications, then relaunches from there.
@MainActor
enum ApplicationMover {
    private static let declinedKey = "moveToApplicationsDeclined"

    /// Returns true when the app is relaunching and this process should quit.
    static func offerIfNeeded() -> Bool {
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
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
            }
            try FileManager.default.copyItem(at: bundleURL, to: destination)
        } catch {
            let failure = NSAlert()
            failure.messageText = String(localized: "Could not move Secreteo.")
            failure.runModal()
            return false
        }
        NSWorkspace.shared.openApplication(at: destination, configuration: .init())
        return true
    }
}
