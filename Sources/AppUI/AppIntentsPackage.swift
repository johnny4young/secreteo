import AppIntents
import DictationSession

/// The intents the app ships come from the libraries, so each package names the next.
public struct AppUIIntentsPackage: AppIntentsPackage {
    public static var includedPackages: [any AppIntentsPackage.Type] { [DictationIntentsPackage.self] }
}
