import SwiftUI

/// First-run setup: dictation, the speech model, and a first try in the practice field.
public struct OnboardingView: View {
    private let dictation: DictationFeature
    private let practiceShown: @MainActor (Bool) -> Void
    private let onFinish: @MainActor () -> Void

    @State private var step = 0
    @State private var modelPreparation = OnboardingModelPreparation()

    private let lastStep = 2

    /// `practiceShown` reports the practice step, because only then may the window hold the field.
    public init(
        dictation: DictationFeature,
        practiceShown: @escaping @MainActor (Bool) -> Void,
        onFinish: @escaping @MainActor () -> Void
    ) {
        self.dictation = dictation
        self.practiceShown = practiceShown
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 0) {
            OnboardingProgress(step: step, count: lastStep + 1)
                .frame(height: 52)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.horizontal, 36)
                .padding(.top, 14)
            footer
        }
        .frame(width: 520, height: 520)
        .onChange(of: step) { _, shown in
            AccessibilityNotification.Announcement(Self.announcement(step: shown, count: lastStep + 1)).post()
        }
        .background(SecreteoDesign.windowBackground)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: OnboardingDictationStep(dictation: dictation)
        case 1:
            OnboardingModelStep(
                dictation: dictation, preparation: modelPreparation,
                prepare: { prepareModels() }, continueWithout: { step += 1 })
        default: practice
        }
    }

    /// Off, or with no model yet, the field shows disabled rather than explaining why.
    private var practice: some View {
        OnboardingPracticeStep(dictation: dictation)
            .disabled(!dictation.practiceIsShown)
            .onAppear { practiceShown(true) }
            .onDisappear { practiceShown(false) }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Skip") { finish() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(SecreteoDesign.tertiaryText)
                .accessibilityIdentifier("onboarding-skip")
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
                    .buttonStyle(OnboardingButtonStyle())
                    .accessibilityIdentifier("onboarding-back")
            }
            Button(step == lastStep ? L10n.text("Done") : L10n.text("Continue")) {
                if step == lastStep { finish() } else { step += 1 }
            }
            .buttonStyle(OnboardingButtonStyle(kind: .primary))
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding-continue")
        }
        .padding(.horizontal, 24)
        .frame(height: 66)
        .overlay(alignment: .top) { Rectangle().fill(SecreteoDesign.hairline).frame(height: 1) }
    }

    /// What VoiceOver says when the step changes: the screen's title, then where it stands.
    nonisolated static func announcement(step: Int, count: Int) -> String {
        let titles = [L10n.text("Dictate Anywhere"), L10n.text("Speech Model"), L10n.text("Try It Here")]
        let title = titles.indices.contains(step) ? titles[step] : ""
        return [title, L10n.format("Step %d of %d", step + 1, count)].filter { !$0.isEmpty }.joined(separator: ". ")
    }

    // MARK: - Actions

    private func prepareModels() {
        Task { @MainActor in
            await modelPreparation.prepare {
                try await dictation.prepareSpeechModel(attempt: modelPreparation.attempt) {
                    modelPreparation.entered($0)
                }
            }
        }
    }

    private func finish() {
        onFinish()
    }
}
