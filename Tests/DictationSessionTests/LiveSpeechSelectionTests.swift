import Foundation
import DictationKit
import XCTest

@testable import DictationSession

@MainActor
final class LiveSpeechSelectionTests: XCTestCase {
    func testAbsentOrCorruptPreferencesDefaultDictationToUltra() async throws {
        let suite = "live-speech-selection-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(LiveSpeechSelection.dictation(defaults: defaults), .parakeetUltra)
        defaults.set("unknown-engine", forKey: LiveSpeechSelection.dictationKey)
        XCTAssertEqual(LiveSpeechSelection.dictation(defaults: defaults), .parakeetUltra)
        defaults.set(LiveSpeechSelection.parakeet.rawValue, forKey: LiveSpeechSelection.dictationKey)
        XCTAssertEqual(LiveSpeechSelection.dictation(defaults: defaults), .parakeet,
                       "an explicit Parakeet choice survives the new default")
    }
}
