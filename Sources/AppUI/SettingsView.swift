import DictationSession
import SwiftUI

public struct SettingsView: View {
    /// The most the tab content takes before it scrolls.
    static let maximumContentHeight: CGFloat = 600

    private let model: AppModel
    private let heightChanged: (CGFloat) -> Void
    @State private var chosenTab: SettingsTab
    @State private var contentHeight: CGFloat = 480
    @State private var showsPortavozImport = false

    public init(
        model: AppModel, tab: SettingsTab = .dictation, heightChanged: @escaping (CGFloat) -> Void = { _ in }
    ) {
        self.model = model
        _chosenTab = State(initialValue: tab)
        self.heightChanged = heightChanged
    }

    public var body: some View {
        VStack(spacing: 0) {
            SettingsTabBar(tabs: tabs, selection: $chosenTab)
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if model.dictationFailedToStart {
                        SettingsCard {
                            Text("Dictation could not start.")
                                .foregroundStyle(SecreteoDesign.notSent)
                                .accessibilityIdentifier("settings-dictation-failed-to-start")
                        }
                    }
                    if let dictation = model.dictation {
                        DictationSettingsPane(dictation: dictation, tab: tab)
                    }
                    if tab == .general { general }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 }
            }
        }
        .frame(width: SettingsMetrics.width)
        .background(SecreteoDesign.windowBackground)
        .ignoresSafeArea()
        .onChange(of: height, initial: true) { heightChanged(height) }
        .modifier(DictationHost(dictation: model.dictation, showsPortavozImport: $showsPortavozImport))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings-root")
        .tint(SecreteoDesign.accent)
    }

    private var tabs: [SettingsTab] {
        model.dictation.map(DictationSettingsPane.tabs) ?? [.general]
    }

    /// A tab that went away with dictation falls back to the first one.
    private var tab: SettingsTab {
        tabs.contains(chosenTab) ? chosenTab : tabs[0]
    }

    private var height: CGFloat {
        SettingsMetrics.barHeight + min(contentHeight, Self.maximumContentHeight)
    }

    @ViewBuilder private var general: some View {
        SettingsEyebrow(Text(verbatim: "Secreteo"))
        SettingsCard {
            SettingsSwitch(Text("Open at Login"), identifier: "settings-launch-at-login", isOn: launchBinding)
            if model.launchAtLoginFailed {
                Text("Could not change this setting.")
                    .foregroundStyle(SecreteoDesign.notSent)
                    .accessibilityIdentifier("settings-launch-at-login-error")
            }
            if let dictation = model.dictation {
                DictationPortavozImportRow(dictation: dictation, showsPortavozImport: $showsPortavozImport)
            }
        }
        SettingsEyebrow(Text("About"))
        SettingsCard {
            SettingsRow(Text("Version")) {
                Text(verbatim: model.versionDescription)
                    .foregroundStyle(SecreteoDesign.secondaryText)
                if model.canCheckForUpdates {
                    Button("Check for Updates…") { model.checkForUpdates() }
                        .accessibilityIdentifier("settings-check-updates")
                }
            }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("settings-version")
            credit(Text("License"), Text(verbatim: "MIT"))
                .accessibilityIdentifier("settings-license")
            // CC BY 4.0 requires naming the authors wherever the models are used.
            credit(Text("Speech Recognition"), Text("Parakeet by NVIDIA, CC BY 4.0"))
                .accessibilityIdentifier("settings-credit-parakeet")
            credit(Text("Voice Detection"), Text("Silero VAD by Silero Team, MIT"))
                .accessibilityIdentifier("settings-credit-silero")
            HStack(spacing: 18) {
                Link(destination: AppModel.sourceCode) { Text("Source Code") }
                    .accessibilityIdentifier("settings-source-code")
                Button("Third-Party Notices") { model.openNotices() }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings-open-notices")
            }
            .fontWeight(.semibold)
            .foregroundStyle(SecreteoDesign.accent)
        }
    }

    private func credit(_ title: Text, _ value: Text) -> some View {
        SettingsRow(title) { value.foregroundStyle(SecreteoDesign.secondaryText) }
            // One element, so the name and its value are read together.
            .accessibilityElement(children: .combine)
    }

    private var launchBinding: Binding<Bool> {
        Binding(get: { model.launchAtLogin }, set: { model.setLaunchAtLogin($0) })
    }
}

/// Dictation's sheets and refreshes, for a build that has dictation.
private struct DictationHost: ViewModifier {
    let dictation: DictationFeature?
    @Binding var showsPortavozImport: Bool

    func body(content: Content) -> some View {
        if let dictation {
            content.modifier(DictationSettingsHost(dictation: dictation, showsPortavozImport: $showsPortavozImport))
        } else {
            content
        }
    }
}
