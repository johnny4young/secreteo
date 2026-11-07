import AppIntents
import Foundation

/// Lets the app's own `AppIntentsPackage` include the intents in this library.
public struct DictationIntentsPackage: AppIntentsPackage {}

// MARK: - Dictation

/// Starts or finishes dictation like the global shortcut. It runs in the
/// background so the app in front stays the destination of the text.
struct DictateIntent: AppIntent {
    static let title: LocalizedStringResource = "Dictate"
    static let description = IntentDescription(
        "Starts dictation into the app in front, or finishes the one in progress, without bringing Secreteo forward.")
    static let supportedModes: IntentModes = [.background]

    @MainActor
    func perform() async throws -> some IntentResult {
        try SecreteoAppIntentBridge.requestDictation(.toggle).throwUnlessAccepted()
        return .result()
    }
}

/// Pastes the last dictation into the app in front, like Paste last.
struct PasteLastDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Paste Last Dictation"
    static let description = IntentDescription(
        "Pastes your last dictation into the app in front, while Secreteo still remembers it.")
    static let supportedModes: IntentModes = [.background]

    @MainActor
    func perform() async throws -> some IntentResult {
        try SecreteoAppIntentBridge.requestDictation(.pasteLast).throwUnlessAccepted()
        return .result()
    }
}

/// Why a dictation action did nothing. Shortcuts shows the message; success stays silent.
enum SecreteoDictationIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notReady
    case dictationOff
    case notOwner
    case unavailable
    case busy
    case nothingToPaste

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .notReady:
            LocalizedStringResource("Secreteo is still opening. Run the action again in a moment.")
        case .dictationOff:
            LocalizedStringResource("Dictation is off. Turn it on in Secreteo Settings.")
        case .notOwner:
            LocalizedStringResource(
                "Another app handles dictation on this Mac. Open Secreteo Settings to use Secreteo.")
        case .unavailable:
            LocalizedStringResource("Dictation is unavailable right now. Open Secreteo Settings to see why.")
        case .busy:
            LocalizedStringResource("Secreteo is finishing the current dictation. Run the action again when it's done.")
        case .nothingToPaste:
            LocalizedStringResource("There's no recent dictation to paste.")
        }
    }
}

/// The handoff between an intent and the running app's dictation.
@MainActor
enum SecreteoAppIntentBridge {
    static let dictationRequested = Notification.Name(
        "com.johnny4young.secreteo.dictation-intent")

    enum DictationRequest: Equatable {
        case toggle
        case pasteLast
    }

    enum DictationRequestOutcome: Equatable {
        case accepted
        case notReady
        case dictationOff
        case notOwner
        case unavailable
        case busy
        case nothingToPaste

        func throwUnlessAccepted() throws {
            switch self {
            case .accepted: return
            case .notReady: throw SecreteoDictationIntentError.notReady
            case .dictationOff: throw SecreteoDictationIntentError.dictationOff
            case .notOwner: throw SecreteoDictationIntentError.notOwner
            case .unavailable: throw SecreteoDictationIntentError.unavailable
            case .busy: throw SecreteoDictationIntentError.busy
            case .nothingToPaste: throw SecreteoDictationIntentError.nothingToPaste
            }
        }
    }

    private static var pendingDictationRequest: DictationRequest?
    private static var dictationOutcome = DictationRequestOutcome.notReady

    /// Answered during the synchronous post and never replayed: dictating
    /// after a slow launch could put text into whatever app is in front then.
    static func requestDictation(_ request: DictationRequest) -> DictationRequestOutcome {
        pendingDictationRequest = request
        dictationOutcome = .notReady
        NotificationCenter.default.post(name: dictationRequested, object: nil)
        pendingDictationRequest = nil
        return dictationOutcome
    }

    static func consumeDictationRequest() -> DictationRequest? {
        defer { pendingDictationRequest = nil }
        return pendingDictationRequest
    }

    static func answerDictationRequest(_ outcome: DictationRequestOutcome) {
        dictationOutcome = outcome
    }
}
