import AppKit
import DictationKit
import UniformTypeIdentifiers

extension DictationFeature {
    /// Explicit local file selection only. The application is neither launched nor registered.
    func selectDictationProfileApplication() async {
        let textSettings = textSettings
        guard textSettings.beginApplicationSelection() else { return }
        defer { textSettings.finishApplicationSelection() }
        guard let window = NSApp.keyWindow else {
            textSettings.reportSelectionError(.unavailableWindow)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if let directory = DictationProfilePickerUITestFixture.directory(
            arguments: launchArguments, environment: ProcessInfo.processInfo.environment,
            usesTemporaryStore: usesTemporaryMeetingStore) {
            panel.directoryURL = directory
        }
        guard await panel.beginSheetModal(for: window) == .OK, let url = panel.url else { return }
        guard let identifier = Bundle(url: url)?.bundleIdentifier,
              DictationTextPreferences.isValidBundleIdentifier(identifier) else {
            textSettings.reportSelectionError()
            return
        }
        // Choosing an application that already has a profile keeps its saved mode.
        let existing = textSettings.profiles.first { $0.bundleIdentifier == identifier }?.mode
        textSettings.setProfile(bundleIdentifier: identifier, mode: existing ?? textSettings.globalMode)
    }
}
