import Foundation
@testable import DictationSession

extension DictationAdmission {
    /// For tests of what happens after admission, which those suites do not vary.
    static var open: Self {
        Self(acquire: { _ in .success(DictationLease()) }, isEligible: { true })
    }

    /// The preference alone, for tests of routing rather than of ownership.
    static func preference(in defaults: UserDefaults) -> Self {
        let isOn = { defaults.bool(forKey: DictationController.defaultsKey) }
        return Self(
            acquire: { kind in
                kind == .practice || isOn() ? .success(DictationLease()) : .failure(.dictationOff)
            },
            isEligible: isOn)
    }
}
