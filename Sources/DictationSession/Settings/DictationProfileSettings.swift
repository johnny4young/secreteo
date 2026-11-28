import AppKit
import DictationKit
import SwiftUI

/// Resolves a saved bundle identifier to its installed macOS app name and icon,
/// falling back to the raw identifier when the app is not present on disk.
struct DictationApplicationDisplay {
    let name: String
    let icon: NSImage?

    static func resolve(
        bundleIdentifier: String,
        knownURL: URL? = nil,
        applicationURL: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        displayName: (String) -> String = { FileManager.default.displayName(atPath: $0) },
        icon: (String) -> NSImage = { NSWorkspace.shared.icon(forFile: $0) }
    ) -> Self {
        let url = applicationURL(bundleIdentifier).flatMap { fileExists($0.path) ? $0 : nil }
            ?? knownURL.flatMap { fileExists($0.path) ? $0 : nil }
        guard let url else {
            return Self(name: bundleIdentifier, icon: nil)
        }
        let raw = displayName(url.path)
        let cleaned = raw.hasSuffix(".app") ? String(raw.dropLast(4)) : raw
        let name = cleaned.isEmpty ? bundleIdentifier : cleaned
        return Self(name: name, icon: icon(url.path))
    }

    static func isInstalled(
        bundleIdentifier: String,
        applicationURL: (String) -> URL? = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) },
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> Bool {
        guard let url = applicationURL(bundleIdentifier) else { return false }
        return fileExists(url.path)
    }
}

/// A text mode and translation per application, saved by bundle identifier.
struct DictationProfileSettings: View {
    let model: DictationTextSettingsModel
    let selectApplication: @MainActor () async -> Void
    @State private var showsProfiles = false

    var body: some View {
        Button {
            showsProfiles.toggle()
            if showsProfiles { model.refreshInstalledPresets() }
        } label: {
            HStack {
                Text("Application Profiles")
                Spacer()
                Image(systemName: showsProfiles ? "chevron.down" : "chevron.right")
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(showsProfiles ? Text("Expanded") : Text("Collapsed"))
        .accessibilityIdentifier("settings-dictation-profiles")
        if showsProfiles { profiles }
    }

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 10) {
            if model.hasInvalidProfiles {
                Text("Application profiles could not be read. Dictation uses the default mode until you reset them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-dictation-profiles-invalid")
                Button("Reset Application Profiles") { model.resetProfiles() }
                    .accessibilityIdentifier("settings-dictation-profile-reset")
            } else {
                ForEach(model.profiles) { profile in
                    profileRow(profile)
                }
                HStack(spacing: 8) {
                    Button("Add Application Profile…") { Task { await selectApplication() } }
                        .disabled(model.isSelectingApplication
                            || model.profiles.count >= DictationTextPreferences.maximumProfiles)
                        .accessibilityIdentifier("settings-dictation-profile-add")
                    Menu {
                        ForEach(DictationProfilePreset.allCases) { preset in
                            let available = model.availableBundleIdentifiers(for: preset)
                            Button(Self.presetTitle(preset)) {
                                model.applyPreset(preset)
                            }
                            .disabled(available.isEmpty
                                || model.profiles.count >= DictationTextPreferences.maximumProfiles)
                            .accessibilityIdentifier("settings-dictation-profile-preset-" + preset.rawValue)
                        }
                    } label: {
                        Text("Add Preset")
                    }
                    .fixedSize()
                    .disabled(model.isSelectingApplication
                        || model.profiles.count >= DictationTextPreferences.maximumProfiles)
                    .accessibilityIdentifier("settings-dictation-profile-presets")
                }
            }
            if let error = model.selectionError {
                selectionErrorText(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-dictation-profile-error")
            }
        }
    }

    private func profileRow(_ profile: DictationApplicationTextProfile) -> some View {
        let display = model.applicationDisplay(for: profile.bundleIdentifier)
        return HStack(spacing: 8) {
            if let icon = display.icon {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
                    .accessibilityHidden(true)
            }
            Text(verbatim: display.name)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(minWidth: 60, alignment: .leading)
                .layoutPriority(-1)
                .help(profile.bundleIdentifier)
                .accessibilityHidden(true)
            Button {
                model.setProfile(
                    bundleIdentifier: profile.bundleIdentifier,
                    preservesCodeTokens: !profile.keepsCodeTokens)
            } label: {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                    .font(.caption2)
                    .foregroundStyle(profile.keepsCodeTokens ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                    .frame(width: 20, height: 20)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L10n.text("Code"))
            .accessibilityLabel(L10n.text("Code") + ": " + display.name)
            .accessibilityValue(profile.keepsCodeTokens ? Text("On") : Text("Off"))
            .accessibilityIdentifier("settings-dictation-profile-code-" + profile.bundleIdentifier)
            Spacer(minLength: 8)
            DictationTextModePicker(
                identifier: "settings-dictation-profile-mode-" + profile.bundleIdentifier,
                label: Text(verbatim: display.name), selection: Binding(
                    get: { profile.choice },
                    set: { model.setProfile(bundleIdentifier: profile.bundleIdentifier, choice: $0) }),
                recipes: model.recipes)
                .labelsHidden()
            DictationTranslationPicker(
                identifier: "settings-dictation-profile-translate-" + profile.bundleIdentifier,
                label: Text(verbatim: L10n.text("Translate Into") + ": " + display.name),
                selection: Binding(
                    get: { profile.translationTarget ?? model.globalTranslationTarget },
                    set: {
                        model.setProfile(bundleIdentifier: profile.bundleIdentifier, translationTarget: $0)
                    }),
                followsDefault: profile.translationTarget == nil,
                onFollowDefault: {
                    model.setProfile(bundleIdentifier: profile.bundleIdentifier, translationTarget: nil)
                })
                .labelsHidden()
                .frame(width: 90)
            Button("Remove") { model.removeProfile(bundleIdentifier: profile.bundleIdentifier) }
                .buttonStyle(.borderless)
                .fixedSize()
                .accessibilityLabel(L10n.text("Remove Application Profile") + ": " + display.name)
                .accessibilityIdentifier("settings-dictation-profile-remove-" + profile.bundleIdentifier)
        }
    }

    private static func presetTitle(_ preset: DictationProfilePreset) -> String {
        switch preset {
        case .chat: L10n.text("Chat")
        case .email: L10n.text("Email")
        case .code: L10n.text("Code / Terminal")
        }
    }

    private func selectionErrorText(_ error: DictationTextSettingsModel.SelectionError) -> Text {
        switch error {
        case .invalidApplication:
            Text("Choose an application with a valid bundle identifier. Profiles are limited to 64.")
        case .unavailableWindow:
            Text("The application chooser needs a Settings window. Open Settings and try again.")
        }
    }
}
