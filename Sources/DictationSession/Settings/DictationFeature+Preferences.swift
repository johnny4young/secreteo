import DictationKit
import Foundation
import Polish
import SwiftUI

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
    }

    func store(_ values: [String: Any]) {
        Self.store(values, in: defaults, temporary: usesTemporaryMeetingStore)
        preferenceRevision += 1
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

    var usesLightweightMemory: Binding<Bool> {
        Binding(
            get: {
                _ = self.preferenceRevision
                return DictationModelMemory.current(in: self.defaults) == .lightweight
            },
            set: {
                let profile: DictationModelMemory = $0 ? .lightweight : .balanced
                self.store([DictationModelMemory.key: profile.rawValue])
                self.modelMemoryChanged()
            })
    }

    var prewarmBinding: Binding<Bool> {
        Binding(
            get: {
                _ = self.preferenceRevision
                // It does nothing with the lightweight profile, so it must not read as on.
                return self.defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey)
                    && DictationModelMemory.current(in: self.defaults) == .balanced
            },
            set: {
                self.store([DictationPrewarmPolicy.defaultsKey: $0])
                self.prewarmIfConfigured()
            })
    }

    var textMode: DictationTextMode {
        _ = preferenceRevision
        return DictationTextPreferences.globalMode(in: defaults)
    }

    var textModeBinding: Binding<DictationTextMode> {
        Binding(
            get: { self.textMode },
            set: { self.store([DictationTextPreferences.modeKey: $0.rawValue]) })
    }

    var foundationModelsCapability: FoundationModelsCapability {
        .current(arguments: launchArguments)
    }

    var polishEngine: DictationPolishEngine {
        _ = preferenceRevision
        return DictationPolishEngine.current(in: defaults, capability: foundationModelsCapability)
    }

    var polishEngineBinding: Binding<DictationPolishEngine> {
        Binding(
            get: { self.polishEngine },
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
