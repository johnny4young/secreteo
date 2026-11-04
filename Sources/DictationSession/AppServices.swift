import DictationKit
import Foundation
import LocalModelStore
import MicCapture

/// What the session asks of the app's composition root, which lives outside this target.
@MainActor
protocol AppServices: AnyObject {
    var defaults: UserDefaults { get }
    var dictationAdmission: DictationAdmission { get }
    var dictationTriggersMayArm: Bool { get }
    var usesTemporaryMeetingStore: Bool { get }
    var dictationShortcutRegistrar: DictationShortcut.Registrar? { get }
    var microphonePermissions: MicrophonePermissionClient { get }
    var modelStore: LocalModelStore { get }
    var dictationPolisher: any DictationTextPolishing { get }
    func makeDictationSessionDependencies() -> DictationSessionDependencies
    func acquireLiveTranscriptionRuntime(for purpose: LiveSpeechPurpose) async throws -> LiveTranscriptionRuntime
}
