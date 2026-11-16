import DictationKit
import SwiftUI

/// What the capsule's rim says about the phase.
enum DictationCapsuleRim: Equatable {
    case quiet, loading, voice, polish, notSent

    /// `transforms`: polishing or translating. A plain paste shares their face but not their copper.
    init(face: SecreteoGlyphFace, transforms: Bool = false) {
        switch face {
        case .listening: self = .voice
        case .loading: self = .loading
        case .polishing: self = transforms ? .polish : .quiet
        case .notSent: self = .notSent
        default: self = .quiet
        }
    }

    /// The colour of each end; the long edges between them carry only a trace of it.
    var ends: (leading: Color, trailing: Color) {
        let quiet = SecreteoPalette.capsuleSecondaryText.color.opacity(0.6)
        switch self {
        case .quiet, .loading: return (quiet, quiet)
        case .voice: return (SecreteoPalette.capsuleAmber.color, SecreteoDesign.ember)
        case .polish: return (SecreteoPalette.capsuleText.color, SecreteoPalette.capsuleAccent.color)
        case .notSent: return (SecreteoPalette.capsuleNotSent.color, SecreteoPalette.capsuleNotSent.color)
        }
    }

    var glows: Bool { self != .quiet && self != .loading }
}

/// When the capsule may animate. Once the microphone has closed, every frame competes with the
/// stop tail and the paste, so nothing does.
enum DictationCapsuleMotion {
    static func settle(microphoneIsOpen: Bool) -> Animation? {
        microphoneIsOpen ? .easeOut(duration: 0.14) : nil
    }

    static func phaseChange(microphoneIsOpen: Bool, reduceMotion: Bool) -> Animation? {
        microphoneIsOpen && !reduceMotion ? .easeOut(duration: 0.2) : nil
    }

    /// The small indicator's faces cross-fade and its capsule grows only while the microphone is open.
    static func indicatorChange(microphoneIsOpen: Bool, duration: TimeInterval) -> Animation? {
        microphoneIsOpen ? .easeOut(duration: duration) : nil
    }

    /// The elapsed time reads the moment of Stop from then on.
    static func clock(tick: Date, stoppedAt: Date?) -> Date { stoppedAt ?? tick }
}

/// How the capsule's one line is shared: the words always keep their part, and the chips give way first.
enum DictationCapsuleBudget {
    static let leading: CGFloat = 16
    static let trailing: CGFloat = 12
    static let spacing: CGFloat = 8
    static let face: CGFloat = 28
    static let cancel: CGFloat = 18
    static let wordsShare: CGFloat = 0.45

    static var content: CGFloat { DictationPanelLayout.width - leading - trailing }
    static var words: CGFloat { (content * wordsShare).rounded(.up) }
    static var chips: CGFloat { content - face - cancel - 3 * spacing - words }

    /// What the chips give up, in order, before the words lose a point.
    enum Density { case full, compact, tight }
}

/// The dictation as one dark-glass parenthesis: its face on the left, the words in the middle,
/// the voice as light rising from below.
struct DictationCapsuleView: View {
    let controller: DictationController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: DictationPanelLayout.noticeSpacing) {
            HStack(spacing: DictationCapsuleBudget.spacing) {
                face
                words.frame(minWidth: DictationCapsuleBudget.words, alignment: .leading).layoutPriority(-1)
                DictationCappedWidth(limit: DictationCapsuleBudget.chips) {
                    ViewThatFits(in: .horizontal) {
                        chips(.full)
                        chips(.compact)
                        chips(.tight)
                    }
                }
                cancel
            }
            .padding(.leading, DictationCapsuleBudget.leading)
            .padding(.trailing, DictationCapsuleBudget.trailing)
            .frame(width: DictationPanelLayout.width, height: DictationPanelLayout.capsuleHeight)
            .background { glass }
            .clipShape(Capsule())
            .overlay { rim }
            .animation(
                DictationCapsuleMotion.phaseChange(microphoneIsOpen: microphoneIsOpen, reduceMotion: reduceMotion),
                value: controller.statusFace)
            if let notice = controller.microphoneNotice {
                Text(notice)
                    .font(.caption)
                    .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 12)
                    .frame(height: DictationPanelLayout.noticeHeight)
                    .background(SecreteoPalette.lacquer.color.opacity(0.94), in: Capsule())
                    .accessibilityIdentifier("dictation-panel-microphone-notice")
            }
        }
        .frame(
            width: DictationPanelLayout.width,
            height: DictationPanelLayout.height(for: controller.phase, showsNotice: controller.microphoneNotice != nil))
        // Dark over any app and in either appearance, so the words stay legible.
        .environment(\.colorScheme, .dark)
    }

    private var face: some View {
        SecreteoGlyph(controller.statusFace, ink: SecreteoPalette.capsuleText.color)
            .frame(width: 28, height: 26)
            .background {
                // The face is the state; its name is there to be read, not seen.
                Text(title)
                    .font(.system(size: 1))
                    .foregroundStyle(.clear)
                    .lineLimit(1)
                    .frame(width: 28, height: 26)
                    .clipped()
                    .accessibilityIdentifier("dictation-panel-state")
            }
            .background {
                if showsModelLoading {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityLabel(L10n.text("Loading the speech model"))
                        .accessibilityIdentifier("dictation-panel-loading")
                }
            }
    }

    @ViewBuilder private var words: some View {
        if case .failed(let message) = controller.phase {
            Text(message)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(SecreteoPalette.capsuleText.color)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        } else if hasWords {
            DictationCapsuleTranscript(
                confirmed: controller.confirmedText, partial: controller.partialText,
                spoken: DictationAssembler.text(confirmed: controller.confirmedText, partial: controller.partialText),
                settle: DictationCapsuleMotion.settle(microphoneIsOpen: microphoneIsOpen))
        } else {
            // No words yet: the state says what is happening, and the hint what to do.
            VStack(alignment: .leading, spacing: 1) {
                stateTitle(size: 13, ink: SecreteoPalette.capsuleText.color)
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .accessibilityIdentifier("dictation-panel-hint")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Seen here, read from the face: one element carries the state for assistive tech.
    private func stateTitle(size: CGFloat, ink: Color) -> some View {
        Text(title)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(ink)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .accessibilityHidden(true)
    }

    private func chips(_ density: DictationCapsuleBudget.Density) -> some View {
        HStack(spacing: 6) {
            if hasWords, controller.phase == .delivering || showsModelLoading {
                stateTitle(size: 12, ink: SecreteoPalette.capsuleSecondaryText.color)
            }
            if let target = controller.targetApp, controller.isActive {
                targetChip(target, named: density == .full)
            }
            if controller.isActive, controller.phase != .delivering {
                pickers(modeLimit: density == .tight ? 48 : 116)
            } else if controller.isPolishing {
                skip(
                    word: L10n.text("unpolished"), action: L10n.text("Paste without polish"),
                    identifiers: ("dictation-panel-skip-polish", "dictation-panel-polish-hint"))
            } else if controller.isTranslating {
                skip(
                    word: L10n.text("untranslated"), action: L10n.text("Paste untranslated"),
                    identifiers: ("dictation-panel-skip-translation", "dictation-panel-translate-hint"))
                if density != .tight {
                    Text(verbatim: "→ " + (density == .full ? translationName : translationCode))
                        .lineLimit(1)
                        .fixedSize()
                        .modifier(DictationCapsuleChip())
                }
            }
            if controller.phase == .listening {
                DictationCapsuleElapsed(start: controller.captureStartedAt, isRunning: microphoneIsOpen)
            }
        }
    }

    /// The app the words go to. Short of room it is only the pencil, and the name moves to its help.
    @ViewBuilder
    private func targetChip(_ target: String, named: Bool) -> some View {
        if named {
            DictationCappedWidth(limit: 96) {
                HStack(spacing: 3) {
                    Image(systemName: "pencil").font(.system(size: 9, weight: .semibold))
                    Text(target)
                        .lineLimit(1)
                        .accessibilityIdentifier("dictation-panel-target")
                }
            }
            .modifier(DictationCapsuleChip(ink: SecreteoPalette.capsuleAccent.color))
        } else {
            Image(systemName: "pencil")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(SecreteoPalette.capsuleAccent.color)
                .frame(width: 14, height: 24)
                .help(target)
                .accessibilityElement()
                .accessibilityLabel(target)
                .accessibilityIdentifier("dictation-panel-target")
        }
    }

    @ViewBuilder
    private func pickers(modeLimit: CGFloat) -> some View {
        DictationTextModePicker(
            identifier: "dictation-panel-text-mode", label: Text("Text mode"),
            selection: Binding(get: { controller.textChoice }, set: { controller.selectTextChoice($0) }),
            recipes: controller.availableRecipes)
            .modifier(DictationCapsuleMenu(maxWidth: modeLimit))
            .disabled(!controller.canChangeTextMode)
        DictationTranslationPicker(
            identifier: "dictation-panel-translate", label: Text("Translate into"),
            selection: Binding(
                get: { controller.translationTarget }, set: { controller.selectTranslationTarget($0) }),
            offSymbol: "translate")
            .modifier(DictationCapsuleMenu(maxWidth: 56))
            .disabled(!controller.canChangeTextMode)
    }

    /// The Esc key drawn as a key: pressing it or clicking it pastes the words as they were said.
    @ViewBuilder
    private func skip(word: String, action: String, identifiers: (button: String, word: String)) -> some View {
        Button { controller.skipPolish() } label: {
            Text(verbatim: "esc")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(SecreteoPalette.capsuleText.color)
                .padding(.horizontal, 5)
                .frame(height: 18)
                .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                .overlay { RoundedRectangle(cornerRadius: 4).strokeBorder(.white.opacity(0.22)) }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(action)
        .accessibilityIdentifier(identifiers.button)
        Text(word)
            .font(.system(size: 12))
            .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
            .fixedSize()
            .accessibilityIdentifier(identifiers.word)
    }

    private var cancel: some View {
        Button { controller.cancel() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.08), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        // A posted paste cannot be recalled; cancelling would only hide its outcome.
        .disabled(controller.phase == .delivering)
        .opacity(controller.phase == .delivering ? 0.4 : 1)
        .accessibilityLabel(L10n.text("Cancel dictation"))
        .accessibilityIdentifier("dictation-panel-cancel")
    }

    @ViewBuilder private var glass: some View {
        if reduceTransparency {
            SecreteoPalette.lacquer.color
        } else {
            Rectangle().fill(.ultraThinMaterial)
            SecreteoPalette.lacquer.color.opacity(0.8)
        }
        if controller.phase == .listening {
            DictationLiquidLevel(
                level: controller.micLevel,
                motion: DictationLiquidShape.motion(microphoneIsOpen: microphoneIsOpen, reduceMotion: reduceMotion),
                paused: !microphoneIsOpen, dimmed: showsModelLoading, opaque: reduceTransparency)
                .equatable()
            // Kept under the controls so it never covers one for assistive tech.
            Color.clear
                .frame(height: 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityElement()
                .accessibilityLabel(L10n.text("Audio level"))
                .accessibilityIdentifier("dictation-panel-meter")
        }
    }

    private var rim: some View {
        let style = DictationCapsuleRim(
            face: controller.statusFace, transforms: controller.isPolishing || controller.isTranslating)
        let ends = style.ends
        // Both ends light up like parentheses; the edges between them stay a hairline.
        let gradient = LinearGradient(
            stops: [
                .init(color: ends.leading, location: 0), .init(color: ends.leading.opacity(0.14), location: 0.056),
                .init(color: ends.trailing.opacity(0.14), location: 0.944), .init(color: ends.trailing, location: 1)
            ],
            startPoint: .leading, endPoint: .trailing)
        let dash: [CGFloat] = style == .loading ? [3, 4] : []
        return ZStack {
            if style.glows {
                Capsule().strokeBorder(gradient, lineWidth: 2.4).blur(radius: 3).opacity(0.75)
            }
            Capsule().strokeBorder(gradient, style: StrokeStyle(lineWidth: 1.2, dash: dash))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var showsModelLoading: Bool { controller.phase == .listening && controller.isLoadingModel }

    private var microphoneIsOpen: Bool { DictationWaveform.animates(for: controller) }

    private var hasWords: Bool { !controller.confirmedText.isEmpty || !controller.partialText.isEmpty }

    private var translationName: String {
        controller.translationTarget == .spanish ? L10n.text("Spanish") : L10n.text("English")
    }

    private var translationCode: String { controller.translationTarget.rawValue.uppercased() }

    private var hint: String? {
        switch controller.phase {
        case .preparing: L10n.text("Preparing microphone…")
        case .listening where showsModelLoading:
            L10n.text("Keep talking. Your words appear once the model is ready.")
        case .listening: L10n.text("Listening…")
        default: nil
        }
    }

    private var title: String {
        switch controller.phase {
        case .preparing:
            return L10n.text("Preparing dictation…")
        case .listening:
            return showsModelLoading ? L10n.text("Loading speech model…") : L10n.text("Dictating")
        case .delivering:
            if controller.isTranslating { return L10n.text("Translating…") }
            return controller.isPolishing ? L10n.text("Polishing…") : L10n.text("Inserting…")
        case .failed(let message):
            return message
        case .idle, .verified, .dispatched, .noSpeech, .recovery:
            return ""
        }
    }
}

/// A quiet chip on the dark glass.
struct DictationCapsuleChip: ViewModifier {
    var ink = SecreteoPalette.capsuleText.color

    func body(content: Content) -> some View {
        content
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(ink)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(.white.opacity(0.08), in: Capsule())
            .overlay { Capsule().strokeBorder(.white.opacity(0.14)) }
    }
}

/// The same chip around a picker, without the system's button chrome.
private struct DictationCapsuleMenu: ViewModifier {
    let maxWidth: CGFloat

    func body(content: Content) -> some View {
        DictationCappedWidth(limit: maxWidth) {
            content
                .labelsHidden()
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .lineLimit(1)
        }
        .modifier(DictationCapsuleChip())
    }
}

/// Hugs its content up to a width, then lets it truncate.
struct DictationCappedWidth: Layout {
    let limit: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let view = subviews.first else { return .zero }
        let size = view.sizeThatFits(ProposedViewSize(width: limit, height: proposal.height))
        return CGSize(width: min(size.width, limit), height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

/// The time since the first audio. It stops counting at Stop instead of ticking through the delivery.
private struct DictationCapsuleElapsed: View {
    let start: Date?
    let isRunning: Bool
    @State private var stoppedAt: Date?

    var body: some View {
        Group {
            if isRunning {
                TimelineView(.periodic(from: .now, by: 1)) { label(at: $0.date) }
            } else {
                label(at: .now)
            }
        }
        .onChange(of: isRunning, initial: true) { stoppedAt = isRunning ? nil : .now }
    }

    private func label(at tick: Date) -> some View {
        Text(DictationCompactIndicator.elapsed(
            since: start, now: DictationCapsuleMotion.clock(tick: tick, stoppedAt: stoppedAt)))
            .font(.system(size: 13, weight: .medium, design: .monospaced))
            .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
            .lineLimit(1)
            .fixedSize()
            .accessibilityIdentifier("dictation-panel-elapsed")
    }
}
