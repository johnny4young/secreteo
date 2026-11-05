import DictationKit
import Foundation
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

    var textMode: DictationTextMode {
        _ = preferenceRevision
        return DictationTextPreferences.globalMode(in: defaults)
    }

    var textModeBinding: Binding<DictationTextMode> {
        Binding(
            get: { self.textMode },
            set: { self.store([DictationTextPreferences.modeKey: $0.rawValue]) })
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
