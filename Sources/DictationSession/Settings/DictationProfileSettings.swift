import DictationKit
import SwiftUI

/// A text mode and translation per application, saved by bundle identifier.
struct DictationProfileSettings: View {
    let model: DictationTextSettingsModel
    let selectApplication: @MainActor () async -> Void
    @State private var showsProfiles = false

    var body: some View {
        Button {
            showsProfiles.toggle()
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
                    HStack {
                        DictationTextModePicker(
                            identifier: "settings-dictation-profile-mode-" + profile.bundleIdentifier,
                            label: Text(verbatim: profile.bundleIdentifier), selection: Binding(
                            get: { profile.choice },
                            set: { model.setProfile(bundleIdentifier: profile.bundleIdentifier, choice: $0) }),
                            recipes: model.recipes)
                        DictationTranslationPicker(
                            identifier: "settings-dictation-profile-translate-" + profile.bundleIdentifier,
                            label: Text("Translate Into"),
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
                        .accessibilityLabel(L10n.text("Remove Application Profile") + ": " + profile.bundleIdentifier)
                        .accessibilityIdentifier("settings-dictation-profile-remove-" + profile.bundleIdentifier)
                    }
                }
                Button("Add Application Profile…") { Task { await selectApplication() } }
                    .disabled(model.isSelectingApplication
                        || model.profiles.count >= DictationTextPreferences.maximumProfiles)
                    .accessibilityIdentifier("settings-dictation-profile-add")
            }
            if let error = model.selectionError {
                selectionErrorText(error)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("settings-dictation-profile-error")
            }
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
