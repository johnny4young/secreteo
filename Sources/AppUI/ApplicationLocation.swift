import Foundation

/// Decides whether to offer moving the app. Running from a disk image or a translocated
/// path breaks launch at login and confuses permission grants.
public enum ApplicationLocation {
    public static func shouldOfferMove(bundleURL: URL, homeDirectory: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.path
        if path.hasPrefix("/Applications/") { return false }
        return !path.hasPrefix(homeDirectory.standardizedFileURL.path + "/Applications/")
    }
}
