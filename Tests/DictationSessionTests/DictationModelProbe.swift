import Foundation

/// Test-only model lane: no microphone, clipboard, settings, database or download.
/// Uses production caption/assembly policies but does NOT stand in for the controller.
enum DictationModelProbe {
    enum Failure: Error, Equatable {
        case invalidInput
        case inputOverflow
        case engineEndedEarly
        case outputOverflow
    }

    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
