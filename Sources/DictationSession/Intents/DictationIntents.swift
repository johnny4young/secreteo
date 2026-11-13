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

/// Saved dictation texts for a Shortcut, newest first. Each request checks
/// the same consent as local agents, in the same read as the rows.
struct SearchDictationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Dictations"
    static let description = IntentDescription(
        // swiftlint:disable:next line_length
        "Finds your saved dictations that contain these words, newest first, then those that say the same in other words. Works only while Secreteo lets agents and Shortcuts read the history.")
    static let supportedModes: IntentModes = [.background]

    @Parameter(title: "Words")
    var words: String?

    @Parameter(title: "Limit", default: 10, inclusiveRange: (1, 50))
    var limit: Int

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<[String]> {
        .result(value: try await SecreteoDictationSearchAction.search(
            words ?? "", limit: limit, reader: SecreteoAppIntentBridge.dictationReader))
    }
}

/// Opens Secreteo on the dictation history, optionally searching for words.
struct OpenDictationsIntent: AppIntent {
    static let title: LocalizedStringResource = "Open Dictations"
    static let description = IntentDescription(
        "Opens your saved dictations in Secreteo, optionally searching for words.")
    static let supportedModes: IntentModes = [.foreground(.immediate)]

    @Parameter(title: "Search")
    var search: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        if SecreteoAppIntentBridge.historyIsUnavailable { throw SecreteoDictationIntentError.unavailable }
        let words = (search ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        SecreteoAppIntentBridge.requestNavigation(.dictations(String(words.prefix(200))))
        return .result()
    }
}

/// App-installed read of saved dictations. nil means the user has not shared
/// the history with agents and Shortcuts; nothing was read.
protocol SecreteoDictationReader: Sendable {
    func dictationTexts(matching words: String, limit: Int) async throws -> [String]?
}

struct UnavailableSecreteoDictationReader: SecreteoDictationReader {
    var error = SecreteoDictationIntentError.notReady

    func dictationTexts(matching _: String, limit _: Int) async throws -> [String]? {
        throw error
    }
}

/// Called by the intent and by tests.
enum SecreteoDictationSearchAction {
    static func search(_ words: String, limit: Int, reader: any SecreteoDictationReader) async throws -> [String] {
        let trimmed = String(words.trimmingCharacters(in: .whitespacesAndNewlines).prefix(200))
        guard let texts = try await reader.dictationTexts(matching: trimmed, limit: min(max(limit, 1), 50)) else {
            throw SecreteoDictationIntentError.notShared
        }
        return texts
    }
}

/// Why a dictation action did nothing. Shortcuts shows the message; success stays silent.
enum SecreteoDictationIntentError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notReady
    case dictationOff
    case notOwner
    case unavailable
    case needsAccessibility
    case busy
    case nothingToPaste
    case notShared

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
        case .needsAccessibility:
            LocalizedStringResource(
                // swiftlint:disable:next line_length
                "Dictation needs the Accessibility permission to type into other apps — grant it in System Settings and try again.")
        case .busy:
            LocalizedStringResource("Secreteo is finishing the current dictation. Run the action again when it's done.")
        case .nothingToPaste:
            LocalizedStringResource("There's no recent dictation to paste.")
        case .notShared:
            LocalizedStringResource(
                "Turn on “Let Agents and Shortcuts Read History” in Secreteo Settings.")
        }
    }
}

/// The handoff between an intent and the running app's dictation.
@MainActor
enum SecreteoAppIntentBridge {
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
        case needsAccessibility
        case busy
        case nothingToPaste

        func throwUnlessAccepted() throws {
            switch self {
            case .accepted: return
            case .notReady: throw SecreteoDictationIntentError.notReady
            case .dictationOff: throw SecreteoDictationIntentError.dictationOff
            case .notOwner: throw SecreteoDictationIntentError.notOwner
            case .unavailable: throw SecreteoDictationIntentError.unavailable
            case .needsAccessibility: throw SecreteoDictationIntentError.needsAccessibility
            case .busy: throw SecreteoDictationIntentError.busy
            case .nothingToPaste: throw SecreteoDictationIntentError.nothingToPaste
            }
        }
    }

    enum NavigationRequest: Equatable {
        /// Dictations, searching for these words when not empty.
        case dictations(String)
    }

    static var dictationReader: any SecreteoDictationReader = UnavailableSecreteoDictationReader()
    /// Set when this launch has no dictation, so no history window will ever open.
    static var historyIsUnavailable = false

    /// The latest destination wins while the app is still opening, and is shown once it can.
    private static var pendingNavigationRequest: NavigationRequest?
    static var navigationHandler: (() -> Void)? {
        didSet { notifyPendingNavigationRequest() }
    }

    static func requestNavigation(_ request: NavigationRequest) {
        pendingNavigationRequest = request
        notifyPendingNavigationRequest()
    }

    static func consumeNavigationRequest() -> NavigationRequest? {
        defer { pendingNavigationRequest = nil }
        return pendingNavigationRequest
    }

    private static func notifyPendingNavigationRequest() {
        guard pendingNavigationRequest != nil else { return }
        navigationHandler?()
    }

    /// Set by the app once it can answer. One handler, so a second feature replaces the first.
    static var dictationHandler: ((DictationRequest) -> DictationRequestOutcome)?

    /// Answered now and never replayed: dictating after a slow launch could put
    /// text into whatever app is in front then.
    static func requestDictation(_ request: DictationRequest) -> DictationRequestOutcome {
        dictationHandler?(request) ?? .notReady
    }
}
