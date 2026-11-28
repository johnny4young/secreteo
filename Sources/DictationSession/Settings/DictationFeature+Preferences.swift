import DictationKit
import Foundation
import Polish
import SwiftUI

/// Three mutually exclusive retention presets backed by `DictationModelMemory` and `DictationPrewarmPolicy`.
enum DictationModelMemoryChoice: String, Equatable, Sendable {
    case lightweight
    case balanced
    case prewarmed
}

/// Lets a view outside Settings, such as the open dictation panel, follow a saved value.
@MainActor
@Observable
final class DictationPreferenceSignal {
    static let shared = DictationPreferenceSignal()
    var revision = 0
}

extension DictationFeature {
    /// A disposable launch runs under the real bundle identifier, so it writes only to its volatile domain.
    /// A real edit supersedes a startup override, or the next session would not read it.
    static func store(_ values: [String: Any], in defaults: UserDefaults, temporary: Bool) {
        var domain = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        for (key, value) in values {
            if temporary {
                domain[key] = value
            } else {
                defaults.set(value, forKey: key)
                domain.removeValue(forKey: key)
            }
        }
        defaults.setVolatileDomain(domain, forName: UserDefaults.argumentDomain)
        DictationPreferenceSignal.shared.revision += 1
    }

    var textSettings: DictationTextSettingsModel {
        if let textSettingsIfCreated { return textSettingsIfCreated }
        let model = DictationTextSettingsModel(defaults: defaults, temporary: usesTemporaryMeetingStore)
        textSettingsIfCreated = model
        return model
    }

    func store(_ values: [String: Any]) {
        Self.store(values, in: defaults, temporary: usesTemporaryMeetingStore)
        if (values[DictationEditLearning.defaultsKey] as? Bool) == false {
            controller.cancelEditLearning()
        }
        preferenceRevision += 1
    }

    var customVocabularyTerms: [String] {
        _ = preferenceRevision
        var seen = Set<String>()
        return DictationVocabularyNormalizer
            .parse(defaults.string(forKey: DictationController.vocabularyKey) ?? "")
            .filter { seen.insert($0.lowercased()).inserted }
    }

    func canLearnReplacement(heard: String, as replacement: String) -> Bool {
        _ = preferenceRevision
        let existing = DictationTextRules.decode(
            replacements: defaults.string(forKey: DictationController.replacementsKey) ?? "")
        return DictationTextRules.learning(heard, as: replacement, into: existing) != nil
    }

    @discardableResult
    func learnReplacement(heard: String, as replacement: String) -> Bool {
        let existing = DictationTextRules.decode(
            replacements: defaults.string(forKey: DictationController.replacementsKey) ?? "")
        guard let updated = DictationTextRules.learning(heard, as: replacement, into: existing) else { return false }
        store([DictationController.replacementsKey: DictationTextRules.encode(updated)])
        return true
    }

    func preference<Value>(_ key: String, default fallback: Value) -> Binding<Value> {
        Binding(
            get: {
                _ = self.preferenceRevision
                return self.defaults.object(forKey: key) as? Value ?? fallback
            },
            set: { self.store([key: $0]) })
    }

    var pasteLastShortcutBinding: Binding<Bool> {
        Binding(
            get: {
                _ = self.preferenceRevision
                return self.defaults.bool(forKey: PasteLastShortcut.defaultsKey)
            },
            set: {
                self.store([PasteLastShortcut.defaultsKey: $0])
                self.syncPasteLastShortcut()
            })
    }

    var modelMemoryChoice: Binding<DictationModelMemoryChoice> {
        Binding(
            get: {
                _ = self.preferenceRevision
                if DictationModelMemory.current(in: self.defaults) == .lightweight { return .lightweight }
                return self.defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey) ? .prewarmed : .balanced
            },
            set: { choice in
                switch choice {
                case .lightweight:
                    self.store([
                        DictationModelMemory.key: DictationModelMemory.lightweight.rawValue,
                        DictationPrewarmPolicy.defaultsKey: false
                    ])
                case .balanced:
                    self.store([
                        DictationModelMemory.key: DictationModelMemory.balanced.rawValue,
                        DictationPrewarmPolicy.defaultsKey: false
                    ])
                case .prewarmed:
                    self.store([
                        DictationModelMemory.key: DictationModelMemory.balanced.rawValue,
                        DictationPrewarmPolicy.defaultsKey: true
                    ])
                }
                self.modelMemoryChanged()
            })
    }

    var foundationModelsCapability: FoundationModelsCapability {
        .current(arguments: launchArguments)
    }

    func polishEngine(capability: FoundationModelsCapability) -> DictationPolishEngine {
        _ = preferenceRevision
        return DictationPolishEngine.current(in: defaults, capability: capability)
    }

    func polishEngineBinding(capability: FoundationModelsCapability) -> Binding<DictationPolishEngine> {
        Binding(
            get: { self.polishEngine(capability: capability) },
            set: { self.store([DictationPolishEngine.defaultsKey: $0.rawValue]) })
    }

    var polishOllamaModelBinding: Binding<String> {
        Binding(
            get: {
                _ = self.preferenceRevision
                return DictationPolishEngine.ollamaModel(in: self.defaults) ?? ""
            },
            set: { self.store([DictationPolishEngine.ollamaModelKey: $0]) })
    }

    /// A disposable launch never asks a real Ollama, so its tests see the same Mac everywhere.
    func ollamaModels() async -> [OllamaService.Model]? {
        guard usesTemporaryMeetingStore else { return await OllamaService.models() }
        if launchArguments.contains("-seed-ollama-empty") { return [] }
        guard launchArguments.contains("-seed-ollama-models") else { return nil }
        return [
            OllamaService.Model(name: "llama3.2:3b", parameterSize: "3.2B", bytes: 2_019_393_189),
            OllamaService.Model(name: "qwen3:8b", parameterSize: "8.2B", bytes: 5_225_376_047)
        ]
    }

    var mouseButton: Int {
        _ = preferenceRevision
        return MouseButtonSetting.load(from: defaults)
    }

    func recordMouseButton(_ button: Int) {
        store([MouseButtonSetting.buttonKey: MouseButtonSetting.isEligible(button) ? button : MouseButtonSetting.off])
        triggersChanged(promptIfNeeded: true)
    }

    func recordShortcut(_ setting: HotkeySetting) {
        store([
            HotkeySetting.keyCodeKey: Int(setting.keyCode),
            HotkeySetting.modifiersKey: Int(setting.modifiers),
            HotkeySetting.labelKey: setting.label
        ])
        triggersChanged()
    }
}
