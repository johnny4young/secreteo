#if SECRETEO_UPDATE_DRYRUN
    import Foundation
    import OSLog

    // Only the release dry run's instrumented build compiles this; scripts/verify_release.py
    // refuses the argument in every other artifact.
    extension DictationFeature {
        public static let updateDryRunHoldArgument = "-secreteo-update-dryrun-hold"

        /// Holds a practice lease through the real coordinator until the named file is deleted,
        /// so Sparkle's relaunch meets a dictation that has not finished.
        public func holdLeaseForUpdateDryRun(arguments: [String] = CommandLine.arguments) {
            guard let flag = arguments.firstIndex(of: Self.updateDryRunHoldArgument),
                  arguments.indices.contains(flag + 1) else { return }
            let sentinel = arguments[flag + 1]
            let logger = Logger(subsystem: "com.johnny4young.secreteo", category: "updates")
            guard case .success(let lease) = ownership.admission.acquire(.practice) else {
                logger.error("The update dry run could not take a lease")
                return
            }
            logger.notice("The update dry run holds a lease")
            Task { @MainActor in
                while FileManager.default.fileExists(atPath: sentinel) {
                    try? await Task.sleep(for: .milliseconds(500))
                }
                logger.notice("The update dry run releases its lease")
                lease.release()
            }
        }
    }
#endif
