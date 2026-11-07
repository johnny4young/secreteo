import Foundation

/// The failure vocabulary and clock the model lanes share; the probe itself is not ported.
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
