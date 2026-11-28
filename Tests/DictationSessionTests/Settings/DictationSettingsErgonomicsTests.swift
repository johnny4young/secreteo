import AppKit
import Foundation
import LiveSpeech
import Testing

@testable import DictationSession

/// Disposable features write the process-wide argument domain, so this suite runs serialized under its guard.
@Suite(.serialized, .exclusiveArgumentDomain)
@MainActor
struct DictationSettingsErgonomicsTests {
    private func makeFeature() throws -> (DictationFeature, UserDefaults, String) {
        let suite = "DictationSettingsErgonomicsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defaults.set(true, forKey: DictationController.defaultsKey)
        let feature = try DictationFeature(
            usesTemporaryStore: true, arguments: [], defaults: defaults,
            environment: .disposable(permissionsAreMissing: false))
        return (feature, defaults, suite)
    }

    @Test
    func applicationDisplayResolvesInstalledStaleKnownAndMissingApps() {
        let icon = NSImage(size: NSSize(width: 16, height: 16))
        let resolved = DictationApplicationDisplay.resolve(
            bundleIdentifier: "com.example.notes",
            applicationURL: { _ in URL(fileURLWithPath: "/Applications/Notes.app") },
            fileExists: { _ in true },
            displayName: { _ in "Notes.app" },
            icon: { _ in icon })
        #expect(resolved.name == "Notes")
        #expect(resolved.icon != nil)

        // A stale LaunchServices URL for a deleted app must fall back instead of showing a generic file icon.
        let stale = DictationApplicationDisplay.resolve(
            bundleIdentifier: "com.example.deleted",
            applicationURL: { _ in URL(fileURLWithPath: "/Volumes/Ejected/Deleted.app") },
            fileExists: { _ in false })
        #expect(stale.name == "com.example.deleted")
        #expect(stale.icon == nil)

        // An unregistered bundle chosen via NSOpenPanel still resolves from its known URL.
        let unregistered = DictationApplicationDisplay.resolve(
            bundleIdentifier: "com.example.fixture",
            knownURL: URL(fileURLWithPath: "/tmp/Fixture.app"),
            applicationURL: { _ in nil },
            fileExists: { $0 == "/tmp/Fixture.app" },
            displayName: { _ in "Fixture.app" },
            icon: { _ in icon })
        #expect(unregistered.name == "Fixture")
        #expect(unregistered.icon != nil)
    }

    @Test
    func aMissingApplicationIsResolvedAgainOnceItAppears() throws {
        let suite = "DictationSettingsErgonomicsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = DictationTextSettingsModel(defaults: defaults, temporary: false)
        var installed = false
        var lookups = 0
        model.resolveApplication = { identifier in
            lookups += 1
            return installed
                ? DictationApplicationDisplay(name: "Notes", icon: NSImage(size: NSSize(width: 16, height: 16)))
                : DictationApplicationDisplay(name: identifier, icon: nil)
        }
        #expect(model.applicationDisplay(for: "com.example.notes").name == "com.example.notes")
        installed = true
        #expect(model.applicationDisplay(for: "com.example.notes").name == "Notes")
        #expect(model.applicationDisplay(for: "com.example.notes").name == "Notes")
        #expect(lookups == 2)
    }

    @Test
    func preferredConcreteLanguageFollowsTheResolvedLocale() {
        #expect(DictationFeature.preferredConcreteLanguage(locale: Locale(identifier: "es_CO")) == "es")
        #expect(DictationFeature.preferredConcreteLanguage(locale: Locale(identifier: "es")) == "es")
        #expect(DictationFeature.preferredConcreteLanguage(locale: Locale(identifier: "en_US")) == "en")
        #expect(DictationFeature.preferredConcreteLanguage(locale: Locale(identifier: "fr_FR")) == "en")
    }

    @Test
    func appleSpeechCoercesAutomaticOrInvalidLanguageOnSwitchAndLaunch() throws {
        let (feature, defaults, suite) = try makeFeature()
        defer { defaults.removePersistentDomain(forName: suite) }

        feature.store([DictationController.languageKey: "auto"])
        feature.speechEngineBinding.wrappedValue = .appleSpeech
        let coerced = feature.dictationLanguageBinding.wrappedValue
        #expect(LiveSpeechSelection.dictationLanguages.contains(coerced))
        #expect(defaults.string(forKey: DictationController.languageKey) == coerced)

        // Leaving Apple Speech gives Parakeet back its Automatic.
        feature.speechEngineBinding.wrappedValue = .parakeet
        #expect(feature.dictationLanguageBinding.wrappedValue == "auto")
        feature.speechEngineBinding.wrappedValue = .appleSpeech

        // A language picked under Apple Speech is kept on the way back.
        feature.dictationLanguageBinding.wrappedValue = "en"
        feature.speechEngineBinding.wrappedValue = .parakeet
        #expect(feature.dictationLanguageBinding.wrappedValue == "en")
        feature.speechEngineBinding.wrappedValue = .appleSpeech

        // Explicit Spanish stays Spanish.
        feature.dictationLanguageBinding.wrappedValue = "es"
        feature.speechEngineChanged()
        #expect(feature.dictationLanguageBinding.wrappedValue == "es")

        // Stale unrecognized language on Apple Speech is coerced during start().
        feature.store([DictationController.languageKey: "fr"])
        feature.start()
        let onLaunch = defaults.string(forKey: DictationController.languageKey) ?? ""
        #expect(LiveSpeechSelection.dictationLanguages.contains(onLaunch))
    }

    @Test
    func modelMemoryChoiceMapsCleanlyToMemoryProfileAndPrewarmPreference() throws {
        let (feature, defaults, suite) = try makeFeature()
        defer { defaults.removePersistentDomain(forName: suite) }

        let expectedDefault: DictationModelMemoryChoice =
            DictationModelMemory.defaultProfile() == .lightweight ? .lightweight : .balanced
        #expect(feature.modelMemoryChoice.wrappedValue == expectedDefault)

        feature.modelMemoryChoice.wrappedValue = .prewarmed
        #expect(feature.modelMemoryChoice.wrappedValue == .prewarmed)
        #expect(DictationModelMemory.current(in: defaults) == .balanced)
        #expect(defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey))

        feature.modelMemoryChoice.wrappedValue = .lightweight
        #expect(feature.modelMemoryChoice.wrappedValue == .lightweight)
        #expect(DictationModelMemory.current(in: defaults) == .lightweight)
        #expect(!defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey))

        feature.modelMemoryChoice.wrappedValue = .balanced
        #expect(feature.modelMemoryChoice.wrappedValue == .balanced)
        #expect(DictationModelMemory.current(in: defaults) == .balanced)
        #expect(!defaults.bool(forKey: DictationPrewarmPolicy.defaultsKey))
    }

    @Test
    func portavozImportIsIdempotentForAppleSpeechAutoAndLightweightPrewarm() throws {
        let suite = "DictationSettingsErgonomicsTests.import.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let portavoz: [String: Any] = [
            LiveSpeechSelection.dictationKey: LiveSpeechSelection.appleSpeech.rawValue,
            DictationController.languageKey: "auto",
            DictationModelMemory.key: DictationModelMemory.lightweight.rawValue,
            DictationPrewarmPolicy.defaultsKey: true
        ]
        let sixteenGB: UInt64 = 16 * 1_024 * 1_024 * 1_024
        let first = PortavozPreferenceImport(portavoz: portavoz, current: defaults, physicalMemory: sixteenGB)
        #expect(first.values[DictationController.languageKey] as? String == DictationFeature.preferredConcreteLanguage())
        #expect(first.values[DictationPrewarmPolicy.defaultsKey] == nil, "lightweight clears prewarm to default false")
        #expect(first.changes.filter { $0.name == L10n.text("Keep Model in Memory") }.count == 1)

        for (key, value) in first.values { defaults.set(value, forKey: key) }
        let second = PortavozPreferenceImport(portavoz: portavoz, current: defaults, physicalMemory: sixteenGB)
        #expect(second.changes.isEmpty, "Re-checking after import must be idempotent")
    }

    @Test
    func portavozImportUsesEightGigabyteLightweightFallbackAccurately() throws {
        let suite = "DictationSettingsErgonomicsTests.import8gb.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let eightGB: UInt64 = 8 * 1_024 * 1_024 * 1_024

        // Already running Lightweight on 8 GB: importing lightweight is a no-op.
        let same = PortavozPreferenceImport(
            portavoz: [DictationModelMemory.key: DictationModelMemory.lightweight.rawValue],
            current: defaults, physicalMemory: eightGB)
        #expect(same.changes.isEmpty)

        // Importing Balanced + Prewarm on 8 GB writes both keys so At Launch sticks.
        let launch = PortavozPreferenceImport(
            portavoz: [
                DictationModelMemory.key: DictationModelMemory.balanced.rawValue,
                DictationPrewarmPolicy.defaultsKey: true
            ],
            current: defaults, physicalMemory: eightGB)
        #expect(launch.values[DictationModelMemory.key] as? String == DictationModelMemory.balanced.rawValue)
        #expect(launch.values[DictationPrewarmPolicy.defaultsKey] as? Bool == true)
    }

    @Test
    func vocabularyEditorMergingRecasesInPlaceAndDeduplicatesMultiTermPastes() {
        #expect(DictationVocabularyEditor.merging("FastAPI", into: "Secreteo, fastapi") == "Secreteo, FastAPI")
        #expect(
            DictationVocabularyEditor.merging("FastAPI, Secreteo\nKubernetes", into: "secreteo")
                == "Secreteo, FastAPI, Kubernetes")
        #expect(DictationVocabularyEditor.merging("   ", into: "Secreteo") == "Secreteo")
    }

    @Test
    func panelWindowResponderCopyValidatesAndCopiesPendingOutputOnlyWhenAvailable() {
        let window = DictationPanelWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 80),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        var pending = false
        var copied = 0
        window.canCopyPendingOutput = { pending }
        window.copyPendingOutput = { copied += 1 }

        let item = NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        #expect(!window.validateUserInterfaceItem(item))
        window.copy(nil)
        #expect(copied == 0)

        pending = true
        #expect(window.validateUserInterfaceItem(item))
        window.copy(nil)
        #expect(copied == 1)
    }
}
