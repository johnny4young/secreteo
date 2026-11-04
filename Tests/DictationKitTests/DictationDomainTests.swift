import DictationKit
import Foundation
import SpeechCore
import Testing

struct DictationRecordTests {
    private func record(
        text: String = "ship it", original: String? = nil, duration: TimeInterval = 3, engine: String = "parakeet",
        applicationName: String? = "Notes"
    ) -> DictationRecord {
        DictationRecord(
            id: DictationRecordID(), createdAt: Date(timeIntervalSince1970: 1_800_000_000), duration: duration,
            text: text, originalText: original, mode: .clean, language: "en", engine: engine,
            applicationName: applicationName, applicationBundleID: nil, delivery: .verified)
    }

    @Test
    func anOriginalEqualToTheTextIsNotKept() {
        #expect(record(text: "ship it", original: "ship it").originalText == nil)
        #expect(record(text: "ship it", original: "um ship it").originalText == "um ship it")
    }

    @Test(arguments: ["", " \n "])
    func blankTextIsInvalid(_ text: String) {
        #expect(!record(text: text).isValid)
    }

    @Test
    func textLengthCountsScalarsUpToTheLimit() {
        let limit = DictationRecord.maximumTextLength
        #expect(record(text: String(repeating: "é", count: limit)).isValid)
        #expect(!record(text: String(repeating: "é", count: limit + 1)).isValid)
    }

    @Test(arguments: [-1, Double.nan, Double.infinity])
    func anImpossibleDurationIsInvalid(_ duration: TimeInterval) {
        #expect(!record(duration: duration).isValid)
    }

    @Test
    func labelsAreBounded() {
        let long = String(repeating: "a", count: DictationRecord.maximumLabelLength + 1)
        #expect(!record(engine: "").isValid)
        #expect(!record(engine: long).isValid)
        #expect(!record(applicationName: long).isValid)
    }

    @Test
    func changingTheDeliveryKeepsEverythingElse() {
        let original = record(text: "ship it", original: "um ship it")

        let changed = original.with(delivery: .notDelivered)

        #expect(changed.delivery == .notDelivered)
        #expect(changed.id == original.id)
        #expect(changed.text == original.text)
        #expect(changed.originalText == original.originalText)
    }

    @Test
    func aPolishedDeliveryReplacesTheTextAndMode() {
        let original = record(text: "ship it")

        let polished = original.with(text: "Ship it.", originalText: "ship it", mode: .polish)

        #expect(polished.text == "Ship it.")
        #expect(polished.originalText == "ship it")
        #expect(polished.mode == .polish)
        #expect(polished.id == original.id)
    }
}

struct DictationHistoryPolicyTests {
    @Test
    func consentStartsOff() {
        #expect(!DictationHistoryPolicy.off.isEnabled)
        #expect(!DictationHistoryPolicy.off.keepsOriginal)
        #expect(!DictationHistoryPolicy.off.agentsCanRead)
    }

    @Test(arguments: [(true, true, true), (true, false, false), (false, true, false), (false, false, false)])
    func agentsReadOnlyWhileTheHistoryIsOn(_ example: (Bool, Bool, Bool)) {
        let policy = DictationHistoryPolicy(
            isEnabled: example.0, keepsOriginal: false, retentionDays: 30, generation: 1, exposesToAgents: example.1)

        #expect(policy.agentsCanRead == example.2)
    }

    @Test(arguments: [
        DictationRecordFilter(query: "report"), DictationRecordFilter(applicationName: "Notes"),
        DictationRecordFilter(onlyNotDelivered: true), DictationRecordFilter(recordID: DictationRecordID())
    ])
    func anyFilterMeansFiltered(_ filter: DictationRecordFilter) {
        #expect(!filter.isUnfiltered)
    }

    @Test
    func aBlankQueryIsUnfiltered() {
        #expect(DictationRecordFilter.all.isUnfiltered)
        #expect(DictationRecordFilter(query: " \n ").isUnfiltered)
    }
}

struct DictationTextChoiceTests {
    @Test(arguments: [DictationTextMode.literal, .clean])
    func aRecipeAppliesOnlyToPolish(_ mode: DictationTextMode) {
        #expect(DictationTextChoice(mode: mode, recipeID: "builtin.formal").recipeID == nil)
        let profile = DictationApplicationTextProfile(bundleIdentifier: "com.example.notes", mode: mode, polishRecipeID: "builtin.formal")
        #expect(profile.polishRecipeID == nil)
    }

    @Test
    func polishKeepsItsRecipe() {
        let profile = DictationApplicationTextProfile(
            bundleIdentifier: "com.example.notes", mode: .polish, polishRecipeID: "builtin.formal")

        #expect(profile.choice == DictationTextChoice(mode: .polish, recipeID: "builtin.formal"))
        #expect(profile.id == "com.example.notes")
    }

    @Test
    func onlyLiteralSkipsTheCleanRules() {
        #expect(!DictationTextMode.literal.appliesCleanRules)
        #expect(DictationTextMode.clean.appliesCleanRules)
        #expect(DictationTextMode.polish.appliesCleanRules)
    }

    @Test
    func translationOffHasNoLanguage() {
        #expect(DictationTranslationTarget.off.languageCode == nil)
        #expect(DictationTranslationTarget.english.languageCode == "en")
        #expect(DictationTranslationTarget.spanish.languageCode == "es")
    }
}

struct DictationRecipeTests {
    private func recipe(name: String = "Short", instruction: String = "Keep it short.") -> DictationRecipe {
        DictationRecipe(id: "custom.short", name: name, instruction: instruction)
    }

    @Test
    func everyBuiltInIsValidAndMarked() {
        #expect(DictationRecipe.builtIns.allSatisfy { $0.isValid && $0.isBuiltIn })
        #expect(!recipe().isBuiltIn)
    }

    @Test
    func nameAndInstructionAreBoundedAndNotBlank() {
        #expect(recipe().isValid)
        #expect(recipe(name: String(repeating: "a", count: DictationRecipe.maximumNameLength)).isValid)
        #expect(!recipe(name: String(repeating: "a", count: DictationRecipe.maximumNameLength + 1)).isValid)
        #expect(recipe(instruction: String(repeating: "a", count: DictationRecipe.maximumInstructionLength)).isValid)
        #expect(!recipe(instruction: String(repeating: "a", count: DictationRecipe.maximumInstructionLength + 1)).isValid)
        #expect(!recipe(name: "  ").isValid)
        #expect(!recipe(instruction: "\n").isValid)
    }
}

struct DictationStatsValueTests {
    private func sample(day: String = "2027-01-15", words: Int = 5, spoken: TimeInterval = 3) -> DictationStatsSample {
        DictationStatsSample(
            id: DictationRecordID(), day: day, words: words, spokenDuration: spoken, applicationName: nil, delivered: true)
    }

    @Test
    func aSampleNeedsADayInTheStoredShapeAndValidCounts() {
        #expect(sample().isValid)
        #expect(!sample(day: "2027-1-15").isValid)
        #expect(!sample(day: "2027/01/15").isValid)
        #expect(!sample(words: -1).isValid)
        #expect(!sample(spoken: .infinity).isValid)
    }

    @Test
    func aSummaryAddsItsDays() {
        let first = DictationStatsTotals(dictations: 1, words: 10, spokenDuration: 4, notDelivered: 2)
        let second = DictationStatsTotals(dictations: 2, words: 20, spokenDuration: 8, notDelivered: 1)
        let summary = DictationStatsSummary(
            days: [DictationStatsDay(day: "2027-01-14", totals: first), DictationStatsDay(day: "2027-01-15", totals: second)],
            topApplications: [])

        #expect(summary.totals == DictationStatsTotals(
            dictations: first.dictations + second.dictations, words: first.words + second.words,
            spokenDuration: first.spokenDuration + second.spokenDuration,
            notDelivered: first.notDelivered + second.notDelivered))
    }
}

struct DictationKitModuleTests {
    private func imports(ofTarget target: String) throws -> Set<String> {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/\(target)")
        var found = Set<String>()
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            let lines = text.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            // Attributes and access levels come before the keyword, as in `@preconcurrency import AppKit`.
            found.formUnion(lines.compactMap { line in
                let words = line.split(separator: " ")
                guard let keyword = words.firstIndex(of: "import"), keyword + 1 < words.count, !line.hasPrefix("//"),
                      words[..<keyword].allSatisfy({ $0.hasPrefix("@") || ["public", "internal", "package"].contains(String($0)) })
                else { return nil }
                return String(words[keyword + 1])
            })
        }
        return found
    }

    @Test
    func speechCoreImportsNoUIStoreOrModels() throws {
        #expect(try imports(ofTarget: "SpeechCore") == ["Foundation"])
    }

    @Test
    func theDomainStaysFreeOfUIAndSessions() throws {
        #expect(try imports(ofTarget: "DictationKit").isSubset(of: ["Foundation", "NaturalLanguage", "SpeechCore"]))
    }
}
