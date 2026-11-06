@testable import AppUI
import Foundation
import Testing

struct FirstRunOnboardingPolicyTests {
    private func decide(force: Bool = false, suppressed: Bool = false, completed: Bool = false)
        -> FirstRunOnboardingDecision {
        FirstRunOnboardingPolicy.decide(FirstRunOnboardingContext(
            forceRequested: force, automationSuppressed: suppressed, hasCompleted: completed))
    }

    @Test func aFirstLaunchShowsSetup() {
        #expect(decide() == .show)
    }

    @Test func aCompletedOrAutomatedLaunchHidesIt() {
        #expect(decide(completed: true) == .hide)
        #expect(decide(suppressed: true) == .hide)
        #expect(decide(suppressed: true, completed: true) == .hide)
    }

    @Test func forcingWinsOverEverySuppression() {
        #expect(decide(force: true, suppressed: true, completed: true) == .show)
        #expect(decide(force: true, suppressed: true) == .show)
        #expect(decide(force: true, completed: true) == .show)
    }

    @Test func onlyATestBuildWithTheTemporaryStoreCanForceIt() {
        let flags = ["-use-temp-store", "-show-onboarding"]
        #expect(RuntimeOptions(arguments: flags, allowsTestFlags: true).forcesOnboarding)
        #expect(!RuntimeOptions(arguments: flags, allowsTestFlags: false).forcesOnboarding)
        #expect(!RuntimeOptions(arguments: ["-show-onboarding"], allowsTestFlags: true).forcesOnboarding)
        #expect(!RuntimeOptions(arguments: ["-use-temp-store"], allowsTestFlags: true).forcesOnboarding)
    }
}

struct FirstRunOnboardingRecordTests {
    private func scratchDefaults() throws -> (UserDefaults, String) {
        let name = "FirstRunOnboardingRecordTests.\(UUID().uuidString)"
        return (try #require(UserDefaults(suiteName: name)), name)
    }

    @Test func finishingIsRememberedForTheNextLaunch() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let record = FirstRunOnboardingRecord(defaults: defaults, isDisposable: false)
        #expect(!record.hasCompleted)
        record.markCompleted()
        #expect(FirstRunOnboardingRecord(defaults: defaults, isDisposable: false).hasCompleted)
    }

    @Test func aDisposableLaunchWritesNothing() throws {
        let (defaults, name) = try scratchDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        FirstRunOnboardingRecord(defaults: defaults, isDisposable: true).markCompleted()
        #expect(defaults.object(forKey: FirstRunOnboardingRecord.key) == nil)
    }
}
