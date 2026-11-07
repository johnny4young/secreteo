import AppIntents
import AppUI

struct SecreteoIntentsPackage: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [AppUIIntentsPackage.self] }
}
