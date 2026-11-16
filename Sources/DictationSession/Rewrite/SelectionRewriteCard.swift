import DictationKit
import SwiftUI

/// The rewrite as a card in the capsule's language: the selection quoted, the recipes as chips,
/// and one copper action once there is a rewrite to accept.
struct SelectionRewriteView: View {
    let controller: SelectionRewriteController
    @FocusState private var focusedChip: SelectionRewriteLayout.ChipStop?
    @FocusState private var replaceIsFocused: Bool
    @Environment(\.layoutDirection) private var layoutDirection

    private typealias Layout = SelectionRewriteLayout

    static func size(for controller: SelectionRewriteController) -> NSSize {
        NSSize(width: Layout.width, height: Layout.height(for: controller.phase, content: content(of: controller)))
    }

    private static func content(of controller: SelectionRewriteController) -> Layout.Content {
        var previewLines = 1
        if case .preview(let text) = controller.phase { previewLines = Layout.previewLines(for: text) }
        return Layout.Content(
            quoteLines: Layout.quoteLines(for: controller.original), previewLines: previewLines,
            showsNotice: controller.notice != nil,
            showsInstruction: controller.spokenInstruction != nil,
            hasResult: controller.result != nil)
    }

    var body: some View {
        let outline = RoundedRectangle(cornerRadius: DictationPanelLayout.cardRadius, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            header
            content
        }
        // The card opens with only its close button; the keyboard belongs on what each phase offers.
        .onChange(of: controller.phase) { _, phase in
            Task { @MainActor in
                switch phase {
                case .choosing: focusedChip = .polish
                case .preview: replaceIsFocused = true
                default: break
                }
            }
        }
        .padding(.horizontal, Layout.horizontalPadding)
        .padding(.vertical, Layout.verticalPadding)
        .frame(
            width: Layout.width,
            height: Layout.height(for: controller.phase, content: Self.content(of: controller)),
            alignment: .topLeading)
        .background { DictationLacquer(tint: 0.92) }
        .clipShape(outline)
        .overlay { DictationRimStroke(style: Layout.rim(for: controller.phase), outline: outline) }
        // Dark over any app and in either appearance, like the capsule.
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack(spacing: 8) {
            SecreteoGlyph(Layout.face(for: controller.phase), ink: SecreteoPalette.capsuleAmber.color)
                .frame(width: 24, height: 22)
            Text(title)
                .font(.system(size: isChoosing ? 14 : 13, weight: .semibold))
                .foregroundStyle(SecreteoPalette.capsuleText.color)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .accessibilityIdentifier("rewrite-state")
            if isChoosing, let name = controller.applicationName {
                Text(L10n.format("in %@", name))
                    .font(.system(size: 12))
                    .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                    .lineLimit(1)
                    .accessibilityIdentifier("rewrite-target")
            }
            if Layout.isBusy(controller.phase) {
                ProgressView().controlSize(.mini)
            }
            Spacer(minLength: 8)
            Button { controller.cancel() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                    .frame(width: 18, height: 18)
                    .background(.white.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .modifier(DictationCardFocusRing(radius: 9, isRound: true))
            .disabled(controller.phase == .replacing)
            .opacity(controller.phase == .replacing ? 0.4 : 1)
            .accessibilityLabel(L10n.text("Cancel rewrite"))
            .accessibilityIdentifier("rewrite-cancel")
        }
        .frame(height: showsOnlyHeader ? Layout.loneHeaderHeight : Layout.headerHeight)
    }

    @ViewBuilder private var content: some View {
        switch controller.phase {
        case .choosing, .rewriting:
            quote.accessibilityIdentifier("rewrite-original")
            if let notice = controller.notice {
                Text(notice)
                    .font(.system(size: 12))
                    .foregroundStyle(SecreteoPalette.capsuleNotSent.color)
                    .lineLimit(2)
                    .frame(height: Layout.noticeHeight, alignment: .topLeading)
                    .padding(.top, Layout.spacing)
                    .accessibilityIdentifier("rewrite-notice")
            }
            if let instruction = controller.spokenInstruction {
                Text(verbatim: "“\(instruction)”")
                    .font(.secreteoSerif(15, italic: true))
                    .foregroundStyle(SecreteoPalette.capsuleSecondaryText.color)
                    .lineLimit(1)
                    .frame(height: Layout.instructionHeight, alignment: .leading)
                    .padding(.top, Layout.spacing)
                    .accessibilityIdentifier("rewrite-instruction")
            }
            chips.padding(.top, Layout.spacing)
            actions { sayHow } trailing: { EmptyView() }
        case .listening:
            quote
            liveInstruction.padding(.top, Layout.spacing)
            actions { EmptyView() } trailing: {
                Button("Done") { controller.finishSayingHow() }
                    .buttonStyle(DictationCardButtonStyle())
                    .modifier(DictationCardFocusRing())
                    .accessibilityIdentifier("rewrite-say-how-done")
            }
        case .preview(let text):
            ScrollView {
                Text(verbatim: text)
                    .font(.secreteoSerif(Layout.quoteSize))
                    .foregroundStyle(SecreteoPalette.capsuleText.color)
                    .lineSpacing(Layout.quoteLineSpacing)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("rewrite-preview")
            }
            .frame(height: Layout.textHeight(
                lines: Layout.previewLines(for: text), maximum: Layout.maximumPreviewLines))
            .padding(.top, Layout.spacing)
            actions {
                Button("Choose another") { controller.chooseAgain() }
                    .buttonStyle(DictationCardButtonStyle())
                    .modifier(DictationCardFocusRing())
                    .accessibilityIdentifier("rewrite-choose-again")
                copyButton
            } trailing: {
                replaceButton
            }
        case .failed:
            if controller.result != nil {
                actions { copyButton } trailing: { EmptyView() }
            }
        case .idle, .capturing, .replacing, .replaced:
            EmptyView()
        }
    }

    /// The selection as it was captured, washed in amber like a marker.
    private var quote: some View {
        var text = AttributedString(controller.original)
        text.swiftUI.backgroundColor = SecreteoPalette.capsuleAmber.color.opacity(0.22)
        let lines = Layout.quoteLines(for: controller.original)
        return Text(text)
            .font(.secreteoSerif(Layout.quoteSize))
            .foregroundStyle(SecreteoPalette.capsuleText.color)
            .lineSpacing(Layout.quoteLineSpacing)
            .lineLimit(lines)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .frame(height: Layout.quoteHeight(lines: lines), alignment: .topLeading)
            .padding(.top, Layout.spacing)
    }

    @ViewBuilder private var liveInstruction: some View {
        let live = controller.liveInstruction
        Group {
            if live.confirmed.isEmpty && live.partial.isEmpty {
                Color.clear
            } else {
                DictationCapsuleTranscript(
                    identifier: "rewrite-live-instruction",
                    confirmed: live.confirmed, partial: live.partial,
                    spoken: DictationAssembler.text(confirmed: live.confirmed, partial: live.partial),
                    settle: DictationCapsuleMotion.settle(microphoneIsOpen: true))
            }
        }
        .frame(height: Layout.liveHeight)
    }

    private var chips: some View {
        let names = controller.recipes.map { DictationTextModePicker.name(of: $0) }
        let widths = ([L10n.text("Polish")] + names).map { Layout.chipWidth(for: $0) }
        let shown = Layout.visibleChips(widths: widths, overflowWidth: Layout.chipWidth(for: L10n.text("More"))) - 1
        let recipes = Array(controller.recipes.enumerated())
        let stops = Layout.chipStops(recipeIDs: controller.recipes.map(\.id), shown: shown)
        let isRewriting = controller.phase == .rewriting
        return HStack(spacing: Layout.chipSpacing) {
            chip(L10n.text("Polish"), stop: .polish, identifier: "rewrite-choice-polish") { controller.choose(nil) }
            ForEach(Array(recipes.prefix(shown)), id: \.element.id) { index, recipe in
                let identifier = "rewrite-choice-" + recipe.id
                chip(names[index], stop: .recipe(recipe.id), identifier: identifier) { controller.choose(recipe) }
            }
            if shown < controller.recipes.count {
                Menu {
                    ForEach(Array(recipes.dropFirst(shown)), id: \.element.id) { index, recipe in
                        Button(names[index]) { controller.choose(recipe) }
                            .accessibilityIdentifier("rewrite-choice-" + recipe.id)
                    }
                } label: {
                    Text("More")
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityAddTraits(isChosen(.more, shown: shown) ? .isSelected : [])
                .accessibilityIdentifier("rewrite-recipes")
                // The chip dims itself, once; the system would dim a disabled menu's label again.
                .environment(\.isEnabled, true)
                .allowsHitTesting(!isRewriting)
                .modifier(SelectionRewriteChip(selected: isChosen(.more, shown: shown)))
                .focused($focusedChip, equals: .more)
                .modifier(DictationCardFocusRing())
            }
        }
        .frame(height: Layout.chipHeight)
        .disabled(isRewriting)
        .onMoveCommand { direction in
            guard let focusedChip, direction == .left || direction == .right else { return }
            let forward = layoutDirection == .leftToRight ? 1 : -1
            self.focusedChip = SettingsArrowKeys.neighbor(
                of: focusedChip, in: stops, by: direction == .right ? forward : -forward)
        }
    }

    private func chip(
        _ name: String, stop: Layout.ChipStop, identifier: String, action: @escaping () -> Void
    ) -> some View {
        let selected = isChosen(stop, shown: 0)
        return Button(name, action: action)
            .buttonStyle(SelectionRewriteChipStyle(selected: selected))
            .focused($focusedChip, equals: stop)
            .modifier(DictationCardFocusRing())
            // A long name is cut in the middle; the whole of it is here.
            .help(name)
            .accessibilityLabel(name)
            .accessibilityAddTraits(selected ? .isSelected : [])
            .accessibilityIdentifier(identifier)
    }

    /// The last choice wears the outline; a spoken instruction is none of the chips.
    private func isChosen(_ stop: Layout.ChipStop, shown: Int) -> Bool {
        guard controller.spokenInstruction == nil else { return false }
        switch stop {
        case .polish: return controller.chosenRecipeID == nil
        case .recipe(let id): return controller.chosenRecipeID == id
        case .more: return controller.recipes.dropFirst(shown).contains { $0.id == controller.chosenRecipeID }
        }
    }

    private var sayHow: some View {
        Button { controller.sayHow() } label: {
            HStack(spacing: 6) {
                SecreteoGlyph(.listening, ink: SecreteoPalette.capsuleAmber.color).frame(width: 15, height: 14)
                Text("Say how")
            }
        }
        .buttonStyle(DictationCardButtonStyle())
        .modifier(DictationCardFocusRing())
        .disabled(controller.phase == .rewriting)
        .help(Text("Or hold your dictation shortcut and say how to rewrite it."))
        .accessibilityIdentifier("rewrite-say-how")
    }

    private var replaceButton: some View {
        Button { controller.replace() } label: {
            HStack(spacing: 6) {
                Text("Replace")
                Text(verbatim: "↩").fontWeight(.medium).opacity(0.7).accessibilityHidden(true)
            }
        }
        .buttonStyle(DictationCardButtonStyle(kind: .primary))
        .focused($replaceIsFocused)
        .modifier(DictationCardFocusRing())
        .keyboardShortcut(.defaultAction)
        .accessibilityIdentifier("rewrite-replace")
    }

    private var copyButton: some View {
        Button(controller.copied ? L10n.text("Copied") : L10n.text("Copy")) { controller.copyResult() }
            .buttonStyle(DictationCardButtonStyle())
            .modifier(DictationCardFocusRing())
            .accessibilityIdentifier("rewrite-copy")
    }

    private func actions(
        @ViewBuilder leading: () -> some View, @ViewBuilder trailing: () -> some View
    ) -> some View {
        HStack(spacing: 8) {
            leading()
            Spacer(minLength: 8)
            trailing()
        }
        .frame(height: Layout.buttonHeight)
        .padding(.top, Layout.actionsSpacing)
    }

    private var isChoosing: Bool { controller.phase == .choosing }

    private var showsOnlyHeader: Bool {
        switch controller.phase {
        case .idle, .capturing, .replacing, .replaced, .failed: true
        case .choosing, .listening, .rewriting, .preview: false
        }
    }

    private var title: String {
        switch controller.phase {
        case .idle: ""
        case .capturing: L10n.text("Reading the selection…")
        case .choosing: L10n.text("Rewrite Selection")
        case .listening: L10n.text("Listening…")
        case .rewriting: L10n.text("Rewriting…")
        case .preview: L10n.text("Preview")
        case .replacing: L10n.text("Replacing…")
        case .replaced:
            controller.applicationName.map { L10n.format("Replaced in %@.", $0) } ?? L10n.text("Replaced.")
        case .failed(let message): message
        }
    }
}

/// A recipe on the card; the last one chosen wears the amber outline.
struct SelectionRewriteChip: ViewModifier {
    let selected: Bool
    @Environment(\.isEnabled) private var isEnabled

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        content
            .font(.system(size: 12, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.middle)
            .foregroundStyle(selected ? SecreteoPalette.capsuleVoiceCrest.color : SecreteoPalette.capsuleText.color)
            .frame(maxWidth: SelectionRewriteLayout.maximumChipLabelWidth)
            .fixedSize()
            .padding(.horizontal, SelectionRewriteLayout.chipPadding)
            .frame(height: SelectionRewriteLayout.chipHeight)
            .background(
                selected ? SecreteoPalette.capsuleAmber.color.opacity(0.16) : .white.opacity(0.09), in: shape)
            .overlay {
                shape.strokeBorder(
                    selected ? SecreteoPalette.capsuleAmber.color : .white.opacity(0.13), lineWidth: selected ? 1.5 : 1)
            }
            .contentShape(shape)
            .opacity(SelectionRewriteLayout.chipOpacity(isEnabled: isEnabled, selected: selected))
    }
}

struct SelectionRewriteChipStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .modifier(SelectionRewriteChip(selected: selected))
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

/// Custom-styled buttons draw no focus ring of their own, so full keyboard access would not show where it is.
struct DictationCardFocusRing: ViewModifier {
    var radius: CGFloat = 9
    var isRound = false
    @FocusState private var isFocused: Bool

    func body(content: Content) -> some View {
        content
            .focused($isFocused)
            .focusEffectDisabled()
            .overlay {
                if isFocused {
                    RoundedRectangle(cornerRadius: isRound ? 99 : radius + 3, style: .continuous)
                        .strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 3)
                        .padding(-3)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
    }
}
