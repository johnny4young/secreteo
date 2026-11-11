import AppKit
import DictationKit
import Testing
import XCTest
@testable import DictationSession

@MainActor
final class DictationSleepTests: XCTestCase {
    func testSleepCancelsCaptureWithoutPastingAndKeepsRecognizedWords() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "No borres estas notas.", controller: controller)
        defer { controller.cancel() }
        var copied: [String] = []
        var dependencies = harness.dependencies
        dependencies.copyText = { copied.append($0); return true }
        controller.toggle(using: dependencies)
        let ready = await TestPolling.until { controller.partialText == harness.text }
        XCTAssertTrue(ready)

        // Without the observer's trailing clear, so a renewed Paste last would show.
        lastText.onSystemSleep?()

        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.recoveryText, harness.text)
        XCTAssertNil(lastText.current, "Sleep must not renew Paste last")
        controller.copyPendingText()
        XCTAssertEqual(copied, [harness.text])
        XCTAssertEqual(controller.copyStatus, .copied)
        let drained = await TestPolling.until { harness.finishes == 1 }
        XCTAssertTrue(drained)
        XCTAssertTrue(harness.insertions.isEmpty)
        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertEqual(controller.recoveryText, harness.text, "Repeated sleep must preserve recovery")
    }

    func testSleepCancelsPreparationBeforeMicrophoneAuthorizationReturns() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Synthetic words", controller: controller)
        let permission = PreparationGate()
        defer { controller.cancel() }
        var dependencies = harness.dependencies
        var released = false
        dependencies.admission = .init(
            acquire: { _ in .success(DictationLease(end: { released = true })) }, isEligible: { true })
        dependencies.authorizeMicrophone = { await permission.wait(); return true }
        controller.toggle(using: dependencies)
        let waiting = await TestPolling.until { permission.started }
        XCTAssertTrue(waiting)
        XCTAssertEqual(controller.phase, .preparing)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        XCTAssertFalse(controller.isActive)
        permission.release()
        let drained = await TestPolling.until { released }
        XCTAssertTrue(drained)
        let starts = await harness.microphone.starts
        XCTAssertEqual(starts, 0)
        XCTAssertTrue(harness.insertions.isEmpty)
    }

    func testDisplaySleepAndExpiryDoNotCancelAnActiveDictation() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Synthetic words", controller: controller)
        defer { controller.cancel() }
        controller.toggle(using: harness.dependencies)
        let ready = await TestPolling.until { controller.partialText == harness.text }
        XCTAssertTrue(ready)

        notifications.post(name: NSWorkspace.screensDidSleepNotification, object: nil)
        lastText.clear()

        XCTAssertTrue(controller.isActive)
        XCTAssertEqual(controller.partialText, harness.text)
    }

    func testSleepWhileModelLoadsStopsCaptureAndReleasesTheLateRuntime() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Synthetic words", controller: controller)
        let model = PreparationGate()
        defer { controller.cancel(); model.release() }
        var dependencies = harness.dependencies
        let acquire = dependencies.acquireRuntime
        dependencies.acquireRuntime = { await model.wait(); return try await acquire() }
        controller.toggle(using: dependencies)
        let waiting = await TestPolling.until { model.started && controller.phase == .listening }
        XCTAssertTrue(waiting)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        model.release()

        let drained = await TestPolling.until { harness.finishes == 1 }
        XCTAssertTrue(drained)
        XCTAssertFalse(controller.isActive)
        XCTAssertTrue(harness.insertions.isEmpty)
    }

    func testSleepDoesNotMoveInternalWordsIntoGlobalRecovery() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Internal instruction", controller: controller)
        defer { controller.cancel() }
        var dependencies = harness.dependencies
        dependencies.deliversInternally = true
        controller.toggle(using: dependencies)
        let ready = await TestPolling.until { controller.partialText == harness.text }
        XCTAssertTrue(ready)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertTrue(controller.recoveryText.isEmpty)
        XCTAssertNil(lastText.current)
        let drained = await TestPolling.until { harness.finishes == 1 }
        XCTAssertTrue(drained)
        XCTAssertTrue(harness.insertions.isEmpty)
    }

    func testSleepDuringStopTailCancelsBeforeLateStopCanDeliver() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Synthetic words", controller: controller)
        let tail = PreparationGate()
        defer { controller.cancel(); tail.release() }
        var dependencies = harness.dependencies
        dependencies.waitForStopTail = { _ in await tail.wait() }
        controller.toggle(using: dependencies)
        let ready = await TestPolling.until { controller.partialText == harness.text }
        XCTAssertTrue(ready)
        harness.now = harness.now.addingTimeInterval(1)
        controller.toggle(using: dependencies)
        let stopping = await TestPolling.until { tail.started }
        XCTAssertTrue(stopping)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        tail.release()

        let drained = await TestPolling.until { harness.finishes == 1 }
        XCTAssertTrue(drained)
        XCTAssertFalse(controller.isActive)
        XCTAssertEqual(controller.recoveryText, harness.text)
        XCTAssertTrue(harness.insertions.isEmpty)
    }

    func testSleepDuringDeliveryWaitsForTheExistingRestoreAndLease() async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Synthetic words", controller: controller)
        let delivery = PreparationGate()
        let restore = PreparationGate()
        defer { controller.cancel(); delivery.release(); restore.release() }
        var released = false
        var dependencies = harness.dependencies
        dependencies.admission = .init(acquire: { _ in
            .success(DictationLease(settle: { await restore.wait() }, end: { released = true }))
        }, isEligible: { true })
        dependencies.captureDestination = {
            CapturedDictationDestination(name: "Synthetic receiver", canRetry: false) { _ in
                await delivery.wait()
                return .dispatched
            }
        }
        controller.toggle(using: dependencies)
        let ready = await TestPolling.until { controller.partialText == harness.text }
        XCTAssertTrue(ready)
        harness.now = harness.now.addingTimeInterval(1)
        controller.toggle(using: dependencies)
        let delivering = await TestPolling.until { delivery.started }
        XCTAssertTrue(delivering)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)

        XCTAssertEqual(controller.phase, .delivering)
        XCTAssertFalse(released)
        delivery.release()
        let restoring = await TestPolling.until { restore.started }
        XCTAssertTrue(restoring)
        XCTAssertFalse(released)
        restore.release()
        let drained = await TestPolling.until { released }
        XCTAssertTrue(drained)
        XCTAssertNil(lastText.current, "A delivery sleep let finish must not renew Paste last")
    }
}

// Text modes live in the process-wide argument domain.
@Suite(.serialized, .exclusiveArgumentDomain, .timeLimit(.minutes(1)))
@MainActor
struct DictationSleepBeforeInsertTests {
    @Test(arguments: [DictationTransformKind.polish, .translate])
    func sleepWhileATransformRunsCancelsWithoutPastingOrRenewingPasteLast(_ kind: DictationTransformKind) async {
        let notifications = NotificationCenter()
        let lastText = DictationLastText(
            workspaceNotifications: notifications, distributedNotifications: NotificationCenter())
        let controller = DictationController(presentsPanel: false, lastText: lastText)
        let harness = DictationControllerHarness(text: "Synthetic words", controller: controller)
        let transform = PreparationGate()
        defer { controller.cancel(); transform.release() }
        var dependencies = harness.dependencies
        switch kind {
        case .polish:
            harness.set(DictationTextMode.polish.rawValue, forKey: DictationTextPreferences.modeKey)
            dependencies.polishDictation = { _, _, _ in
                await transform.wait()
                return .polished("Polished synthetic words.")
            }
        case .translate:
            harness.set(DictationTranslationTarget.spanish.rawValue, forKey: DictationTextPreferences.translationKey)
            harness.set("en", forKey: DictationController.languageKey)
            dependencies.translateDictation = { _, _, _ in
                await transform.wait()
                return .translated("Palabras sintéticas")
            }
        }
        controller.toggle(using: dependencies)
        let ready = await TestPolling.until { controller.partialText == harness.text }
        #expect(ready)
        harness.now = harness.now.addingTimeInterval(1)
        controller.toggle(using: dependencies)
        let transforming = await TestPolling.until { transform.started && controller.phase == .delivering }
        #expect(transforming)

        notifications.post(name: NSWorkspace.willSleepNotification, object: nil)
        transform.release()

        let drained = await TestPolling.until { harness.finishes == 1 }
        #expect(drained)
        #expect(!controller.isActive)
        #expect(controller.recoveryText == harness.text)
        #expect(harness.insertions.isEmpty)
        #expect(lastText.current == nil)
    }
}
