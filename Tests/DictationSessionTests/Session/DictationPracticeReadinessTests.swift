import Foundation
import DictationKit
import DictationOwnership
import Synchronization
import Testing

@testable import DictationSession
@testable import MicCapture

@Suite(.serialized, .exclusiveArgumentDomain, .timeLimit(.minutes(1)))
@MainActor
struct DictationPracticeReadinessTests {
    @Test
    func globalReadinessRequiresPracticeAfterModelAndPermissions() {
        let microphone = Mutex(false)
        let accessibility = Mutex(false)
        let gap = ReadinessGap(
            isDisposable: false,
            microphone: MicrophonePermissionClient(
                state: { microphone.withLock { $0 } ? .authorized : .denied }, request: { false }),
            accessibilityIsGranted: { accessibility.withLock { $0 } })
        #expect(gap.current() == ReadinessGap.missingModel)
        gap.modelIsReady.withLock { $0 = true }
        #expect(gap.current() == "microphone")
        microphone.withLock { $0 = true }
        #expect(gap.current() == "accessibility")
        accessibility.withLock { $0 = true }
        #expect(gap.current() == ReadinessGap.missingPractice)
        gap.practiceIsComplete.withLock { $0 = true }
        #expect(gap.current() == nil)
        microphone.withLock { $0 = false }
        #expect(gap.current() == "microphone", "Completion cannot bypass revoked permissions")
    }

    @Test
    func practiceRemainsAvailableBeforeGlobalOwnership() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: DictationController.defaultsKey)
            let gap = readyGap()
            let coordinator = DictationOwnershipCoordinator.live(
                defaults: defaults, usesTemporaryStore: true, missingForReadiness: { gap.current() })
            coordinator.start()
            #expect(coordinator.state == .preparing)
            #expect(!coordinator.armsTriggers)
            let practice = try coordinator.admission.acquire(.practice).get()
            practice.release()
            gap.practiceIsComplete.withLock { $0 = true }
            coordinator.reevaluate()
            #expect(coordinator.state == .available)
            #expect(!coordinator.armsTriggers, "Completion alone does not take ownership")
        }
    }

    @Test
    func anExistingOwnerCannotAdmitGlobalWorkWithoutPractice() async throws {
        try await withDefaults { defaults in
            defaults.set(true, forKey: DictationController.defaultsKey)
            let gap = readyGap()
            let coordinator = DictationOwnershipCoordinator.live(
                defaults: defaults, usesTemporaryStore: true, missingForReadiness: { gap.current() })
            coordinator.claimScratchOwnership()
            coordinator.start()
            #expect(coordinator.state == .unavailable(.notReady(ReadinessGap.missingPractice)))
            #expect(!coordinator.armsTriggers)
            switch coordinator.admission.acquire(.global) {
            case .success(let lease):
                lease.release()
                Issue.record("An unpracticed owner admitted global work")
            case .failure: break
            }
            gap.practiceIsComplete.withLock { $0 = true }
            coordinator.reevaluate()
            #expect(coordinator.state == .owned)
            let lease = try coordinator.admission.acquire(.global).get()
            lease.release()
        }
    }

    @Test
    func onlySuccessfulPracticePersistsCompletionAndNeverItsWords() async throws {
        try await withDefaults { defaults in
            let feature = try DictationFeature(usesTemporaryStore: true, arguments: [], defaults: defaults)
            #expect(!feature.readiness.practiceIsComplete.withLock { $0 })
            #expect(feature.practice.receive("private fixture words") == .refused(.targetChanged))
            #expect(!defaults.bool(forKey: ReadinessGap.practiceCompletionKey))
            let holder = UUID()
            feature.practice.show(holder, isKey: true)
            #expect(feature.practice.receive(" \n ") == .refused(.emptyText))
            #expect(!defaults.bool(forKey: ReadinessGap.practiceCompletionKey))
            #expect(feature.practice.receive("private fixture words") == .verified)
            #expect(defaults.bool(forKey: ReadinessGap.practiceCompletionKey))
            let volatile = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
            #expect(
                volatile[ReadinessGap.practiceCompletionKey] as? Bool == true, "Disposable launches never persist it")
            #expect(feature.readiness.practiceIsComplete.withLock { $0 })
            feature.practice.clear()
            feature.practice.hide(holder)
            #expect(feature.practice.text.isEmpty)
            #expect(defaults.bool(forKey: ReadinessGap.practiceCompletionKey))
            let relaunched = try DictationFeature(usesTemporaryStore: true, arguments: [], defaults: defaults)
            #expect(relaunched.readiness.practiceIsComplete.withLock { $0 })
            #expect(relaunched.practice.text.isEmpty)
            #expect(!String(describing: defaults.dictionaryRepresentation()).contains("private fixture words"))
        }
    }

    @Test
    func aRoutedDestinationClosedBeforeDeliveryCannotCompletePractice() async throws {
        try await withDefaults { defaults in
            let feature = try DictationFeature(usesTemporaryStore: true, arguments: [], defaults: defaults)
            let holder = UUID()
            feature.practice.show(holder, isKey: true)
            let routed = feature.practice.route(feature.makeDictationSessionDependencies(), appIsActive: true)
            let destination = routed.captureDestination()
            feature.practice.hide(holder)
            #expect(await destination.insert("late fixture") == .refused(.targetChanged))
            #expect(!defaults.bool(forKey: ReadinessGap.practiceCompletionKey))
        }
    }

    @Test
    func disablingDictationBeforePracticeDeliveryRefusesCompletion() async throws {
        try await withDefaults { defaults in
            let feature = try DictationFeature(usesTemporaryStore: true, arguments: [], defaults: defaults)
            feature.settingsWindowChanged(isKey: true)
            let routed = feature.practice.route(
                feature.makeDictationSessionDependencies(), appIsActive: true,
                isStillShown: { feature.practiceIsShown })
            let destination = routed.captureDestination()
            feature.setEnabled(false)
            #expect(feature.practice.isArmed, "The settings window still owns its holder")
            #expect(await destination.insert("late hidden fixture") == .refused(.targetChanged))
            #expect(feature.practice.text.isEmpty)
            #expect(!defaults.bool(forKey: ReadinessGap.practiceCompletionKey))
            feature.settingsWindowClosed()
        }
    }

    @Test
    func incompletePracticeDoesNotPollModelFilesAtThePermissionRate() {
        #expect(DictationFeature.readinessPollDelay(missing: ReadinessGap.missingPractice) == .seconds(30))
    }

    private func readyGap() -> ReadinessGap {
        let gap = ReadinessGap(
            isDisposable: false,
            microphone: MicrophonePermissionClient(state: { .authorized }, request: { false }),
            accessibilityIsGranted: { true })
        gap.modelIsReady.withLock { $0 = true }
        return gap
    }

    private func withDefaults(_ body: @MainActor (UserDefaults) async throws -> Void) async throws {
        let name = "practice-readiness-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(true, forKey: DictationController.defaultsKey)
        try await body(defaults)
    }
}
