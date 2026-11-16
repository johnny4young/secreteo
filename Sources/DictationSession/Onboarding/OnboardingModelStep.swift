import SwiftUI

/// The speech model's preparation as the capsule filling from the left, over one card per model.
struct OnboardingModelStep: View {
    let dictation: DictationFeature
    let preparation: OnboardingModelPreparation
    let prepare: () -> Void
    let continueWithout: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OnboardingTitle(title: L10n.text("Speech Model"), identifier: "onboarding-model")
            status.padding(.top, 32)
            if case .failed(let failure) = preparation.phase {
                Text(failure.message)
                    .font(.system(size: 13))
                    .foregroundStyle(SecreteoDesign.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
                    .accessibilityIdentifier("onboarding-model-error")
                Button("Continue Without the Model", action: continueWithout)
                    .buttonStyle(OnboardingButtonStyle(isCompact: true))
                    .padding(.top, 10)
                    .accessibilityIdentifier("onboarding-model-continue-without")
            }
            cards.padding(.top, 20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var status: some View {
        switch preparation.phase {
        case .idle:
            Button(action: prepare) {
                OnboardingModelCapsule(face: .ready, fraction: 0) { Text("Prepare") }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-model-prepare")
        case .preparing:
            let fraction = preparation.fraction
            let isWarming = preparation.isWarming
            // Warming up has no measure: a full capsule with light passing over it, and no number.
            OnboardingModelCapsule(
                face: .loading, fraction: isWarming ? 1 : fraction ?? 0, isIndeterminate: isWarming
            ) {
                // On the text, not the container: a container identifier stamps every descendant on macOS.
                (isWarming ? Text("Warming up") : Text("Preparing the speech model for this Mac"))
                    .accessibilityIdentifier("onboarding-model-preparing")
                Spacer(minLength: 8)
                if let fraction {
                    Text(verbatim: "\(Int(fraction * 100))%")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .accessibilityIdentifier("onboarding-model-percent")
                }
            }
            .onChange(of: dictation.modelDownloadFraction, initial: true) { _, reported in
                preparation.downloaded(reported)
            }
        case .ready:
            OnboardingModelCapsule(face: .inserted, fraction: 1) {
                Text("Ready").accessibilityIdentifier("onboarding-model-ready")
            }
        case .failed:
            Button(action: prepare) {
                OnboardingModelCapsule(face: .notSent, fraction: 0) { Text("Try Again") }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("onboarding-model-retry")
        }
    }

    private var cards: some View {
        HStack(alignment: .top, spacing: 12) {
            if dictation.speechModelIsRequired {
                card(
                    Text("Parakeet"), preparation.speechStatus(isInstalled: dictation.speechModelIsInstalled),
                    identifier: "onboarding-model-speech-status")
            }
            card(
                Text("Voice Detector"), preparation.detectorStatus(isInstalled: dictation.detectorIsInstalled),
                identifier: "onboarding-model-detector-status")
        }
    }

    private func card(_ name: Text, _ status: OnboardingModelPreparation.PartStatus, identifier: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            name.font(.system(size: 14.5, weight: .semibold)).foregroundStyle(SecreteoDesign.text)
            Text(status.label)
                .font(.system(size: 12.5, weight: status.isReady ? .semibold : .regular))
                .foregroundStyle(status.isReady ? SecreteoDesign.verified : SecreteoDesign.tertiaryText)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(identifier)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onboardingCard(cornerRadius: 14)
    }

    /// Where the passing light starts, for a time in seconds: from off the left edge to off the right.
    nonisolated static func sweepOffset(at time: TimeInterval, width: CGFloat) -> CGFloat {
        let phase = time.truncatingRemainder(dividingBy: sweepPeriod) / sweepPeriod
        return width * ((1 + sweepShare) * phase - sweepShare)
    }

    nonisolated static let sweepPeriod: TimeInterval = 1.8
    nonisolated static let sweepShare: CGFloat = 0.35
}

extension OnboardingModelPreparation.PartStatus {
    var isReady: Bool { self == .ready(copied: false) }

    var label: String {
        switch self {
        case .missing: L10n.text("Not Downloaded")
        case .downloading: L10n.text("Downloading")
        case .copying: L10n.text("Copying from Portavoz")
        case .installed(copied: true): L10n.text("Copied from Portavoz")
        case .installed(copied: false): L10n.text("Downloaded")
        case .ready(copied: true): L10n.text("Copied from Portavoz")
        case .ready(copied: false): L10n.text("Ready")
        }
    }
}

/// The dictation capsule's lacquer, with the progress as light entering from the left.
private struct OnboardingModelCapsule<Content: View>: View {
    let face: SecreteoGlyphFace
    let fraction: Double
    var isIndeterminate = false
    @ViewBuilder let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 10) {
            SecreteoGlyph(face, ink: SecreteoPalette.capsuleText.color).frame(width: 28, height: 26)
            content
        }
        .font(.system(size: 14.5, weight: .medium))
        .foregroundStyle(SecreteoPalette.capsuleText.color)
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.leading, 18)
        .padding(.trailing, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: DictationPanelLayout.capsuleHeight)
        .background { fill }
        .clipShape(Capsule())
        .overlay { Capsule().strokeBorder(SecreteoPalette.capsuleSecondaryText.color.opacity(0.2)) }
        .contentShape(Capsule())
        .environment(\.colorScheme, .dark)
    }

    private var fill: some View {
        GeometryReader { proxy in
            let width = proxy.size.width * min(max(fraction, 0), 1)
            ZStack(alignment: .leading) {
                LinearGradient(
                    colors: [SecreteoPalette.capsuleHighlight.color, SecreteoPalette.lacquer.color],
                    startPoint: .top, endPoint: .bottom)
                LinearGradient(
                    colors: [SecreteoPalette.accent.color, SecreteoDesign.ember, SecreteoPalette.capsuleAmber.color],
                    startPoint: .leading, endPoint: .trailing)
                    // Dim enough that the words over it keep their contrast.
                    .opacity(0.38)
                    .frame(width: width)
                if isIndeterminate, !reduceMotion {
                    TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                        LinearGradient(
                            colors: [.clear, SecreteoPalette.capsuleVoiceCrest.color.opacity(0.22), .clear],
                            startPoint: .leading, endPoint: .trailing)
                            .frame(width: proxy.size.width * OnboardingModelStep.sweepShare)
                            .offset(x: OnboardingModelStep.sweepOffset(
                                at: context.date.timeIntervalSinceReferenceDate, width: proxy.size.width))
                    }
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.3), value: fraction)
        }
        .accessibilityHidden(true)
    }
}
