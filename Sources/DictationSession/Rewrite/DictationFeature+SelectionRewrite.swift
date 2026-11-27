import AppKit
import Carbon.HIToolbox
import DictationKit
import Foundation
import SwiftUI

/// Optional fixed shortcut for rewriting the selection; off by default.
enum RewriteSelectionShortcut {
    static let defaultsKey = "dictationRewriteSelectionHotkey"
    static let setting = HotkeySetting(
        keyCode: UInt32(kVK_ANSI_R), modifiers: UInt32(controlKey | optionKey | cmdKey), label: "⌃⌥⌘R")
}

extension DictationFeature {
    public func rewriteSelection() {
        selectionRewrite.start(using: makeSelectionRewriteDependencies())
    }

    func makeDictationSessionDependencies(capturesInstruction: Bool) -> DictationSessionDependencies {
        let routed = practice.route(
            unroutedDependencies(), appIsActive: NSApplication.shared.isActive && practiceIsShown,
            isStillShown: { [weak self] in self?.practiceIsShown == true })
        // A rewrite waiting for "Say how" takes the next session's words as its instruction.
        return capturesInstruction && selectionRewrite.capturesInstruction
            ? selectionRewrite.instructionDependencies(routed) : routed
    }

    func syncRewriteSelectionShortcut() {
        rewriteSelectionRegistration?.unregister()
        rewriteSelectionRegistration = nil
        let wanted = !isRecordingShortcut && dictationTriggersMayArm
            && defaults.bool(forKey: DictationController.defaultsKey)
            && defaults.bool(forKey: RewriteSelectionShortcut.defaultsKey)
        guard wanted, let fixedShortcutRegistrar else {
            rewriteSelectionShortcutIsUnavailable = false
            return
        }
        rewriteSelectionRegistration = fixedShortcutRegistrar(
            RewriteSelectionShortcut.setting, { [weak self] in self?.rewriteSelection() }, {})
        rewriteSelectionShortcutIsUnavailable = rewriteSelectionRegistration == nil
    }

    var rewriteSelectionShortcutBinding: Binding<Bool> {
        Binding(
            get: {
                _ = self.preferenceRevision
                return self.defaults.bool(forKey: RewriteSelectionShortcut.defaultsKey)
            },
            set: {
                self.store([RewriteSelectionShortcut.defaultsKey: $0])
                self.syncRewriteSelectionShortcut()
            })
    }

    func makeSelectionRewriteDependencies() -> SelectionRewriteController.Dependencies {
        let defaults = defaults
        let recipes = { DictationTextPreferences.recipes(in: defaults) }
        let terms = {
            DictationTextRules.decode(
                replacements: defaults.string(forKey: DictationController.replacementsKey) ?? ""
            ).map(\.replacement)
        }
        let vocabulary = {
            DictationVocabularyNormalizer.parse(defaults.string(forKey: DictationController.vocabularyKey) ?? "")
        }
        var dependencies = usesTemporaryMeetingStore
            ? SelectionRewriteUITestFixture(arguments: launchArguments)
                .dependencies(admission: dictationAdmission, recipes: recipes)
            : liveSelectionRewriteDependencies(recipes: recipes, terms: terms, vocabulary: vocabulary)
        dependencies.startDictation = { [weak self] in self?.toggleDictation() }
        dependencies.finishDictation = { [weak self] in self?.controller.finishAndInsert() }
        dependencies.isDictating = { [weak self] in self?.controller.isActive ?? false }
        dependencies.capsuleIsShown = { [weak self] in self?.controller.panel.isShown ?? false }
        dependencies.liveInstruction = { [weak self] in
            (self?.controller.confirmedText ?? "", self?.controller.partialText ?? "")
        }
        return dependencies
    }

    private func liveSelectionRewriteDependencies(
        recipes: @escaping () -> [DictationRecipe],
        terms: @escaping () -> [String],
        vocabulary: @escaping () -> [String]
    ) -> SelectionRewriteController.Dependencies {
        SelectionRewriteController.Dependencies(
            admission: dictationAdmission,
            capture: { await TextInserter.captureSelection() },
            polish: { [polisher = dictationPolisher] text, protectedTerms, recipe in
                let vocab = vocabulary()
                return await PolishDictation(polisher: polisher, timeout: SelectionRewriteController.timeout)(
                    text, protectedTerms: protectedTerms, vocabulary: vocab, recipe: recipe)
            },
            recipes: recipes,
            protectedTerms: terms,
            copyText: { TextInserter.copy($0) },
            registerKey: { keyCode, onPress in GlobalHotkey(keyCode: keyCode, modifiers: 0, onPress: onPress) })
    }
}

/// Disposable launches rewrite a fixed selection with no Accessibility, clipboard or engine.
@MainActor
struct SelectionRewriteUITestFixture {
    static let text = "Don't delete these notes."
    let selectsNothing: Bool
    let selectionChanges: Bool

    init(arguments: [String]) {
        selectsNothing = arguments.contains("-seed-rewrite-nothing-selected")
        selectionChanges = arguments.contains("-seed-rewrite-selection-changes")
    }

    func dependencies(
        admission: DictationAdmission, recipes: @escaping () -> [DictationRecipe]
    ) -> SelectionRewriteController.Dependencies {
        let selectsNothing = selectsNothing
        let selectionChanges = selectionChanges
        return SelectionRewriteController.Dependencies(
            admission: admission,
            capture: {
                guard !selectsNothing else { return .failure(.nothingSelected) }
                return .success(CapturedSelection(
                    text: Self.text, source: .accessibility, applicationName: "Rewrite test receiver",
                    revalidate: { selectionChanges ? .selectionChanged : nil },
                    destination: CapturedDictationDestination(
                        name: "Rewrite test receiver", canRetry: false) { _ in .verified }))
            },
            polish: { text, terms, recipe in
                await DictationUITestFixture.polishing(nil)(text, terms, [], recipe)
            },
            recipes: recipes,
            protectedTerms: { [] },
            copyText: { _ in true },
            wait: DictationUITestFixture.waitHoldingFeedback)
    }
}
