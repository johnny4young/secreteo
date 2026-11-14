import Foundation
import XCTest

extension XCTestCase {
    /// Empties the process-wide argument domain, which outranks every suite, until this test ends.
    func isolateArgumentDomain() {
        let defaults = UserDefaults.standard
        // Read and written only here and in the teardown, which XCTest runs after the test body.
        nonisolated(unsafe) let original = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        defaults.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
        addTeardownBlock { UserDefaults.standard.setVolatileDomain(original, forName: UserDefaults.argumentDomain) }
    }
}
