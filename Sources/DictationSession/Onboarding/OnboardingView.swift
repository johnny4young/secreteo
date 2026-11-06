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
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(28)
            footer
        }
        .frame(width: 520, height: 520)
    }

    @ViewBuilder private var content: some View {
        switch step {
        case 0: OnboardingDictationStep(dictation: dictation)
        case 1: models
        default: practice
        }
    }

    private var models: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speech Model")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding-model")
            modelPreparationStatus
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Off, or with no model yet, the field shows disabled rather than explaining why.
    private var practice: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Try It Here")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("onboarding-practice")
            DictationPracticeView(dictation: dictation, identifiers: .onboarding)
                .disabled(!dictation.practiceIsShown)
        }
        .onAppear { practiceShown(true) }
        .onDisappear { practiceShown(false) }
    }

    // MARK: - Chrome

    private var footer: some View {
        HStack {
            Button("Skip") { finish() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("onboarding-skip")
            Spacer()
            if step > 0 {
                Button("Back") { step -= 1 }
                    .accessibilityIdentifier("onboarding-back")
            }
            Button(step == lastStep ? L10n.text("Done") : L10n.text("Continue")) {
                if step == lastStep { finish() } else { step += 1 }
            }
            .keyboardShortcut(.defaultAction)
            .accessibilityIdentifier("onboarding-continue")
        }
        .padding(20)
        .background(.bar)
    }

    // MARK: - Actions

    private func prepareModels() {
        Task { @MainActor in
            await modelPreparation.prepare {
                try await dictation.prepareSpeechModel(attempt: modelPreparation.attempt)
            }
        }
    }

    private func finish() {
        onFinish()
    }
}

private extension OnboardingView {
    @ViewBuilder var modelPreparationStatus: some View {
        switch modelPreparation.phase {
        case .ready:
            Label("Ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .accessibilityIdentifier("onboarding-model-ready")
        case .preparing:
            HStack(spacing: 10) {
                ProgressView().controlSize(.small)
                // On the text, not the container: a container identifier
                // stamps every descendant on macOS.
                Text("Preparing the speech model for this Mac").font(.callout).foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding-model-preparing")
            }
        case .failed(let failure):
            VStack(alignment: .leading, spacing: 10) {
                Text(failure.message)
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("onboarding-model-error")
                HStack {
                    Button("Try Again") { prepareModels() }
                        .accessibilityIdentifier("onboarding-model-retry")
                    Button("Continue Without the Model") { step += 1 }
                        .accessibilityIdentifier("onboarding-model-continue-without")
                }
            }
        case .idle:
            Button("Prepare") { prepareModels() }
                .accessibilityIdentifier("onboarding-model-prepare")
        }
    }
}
