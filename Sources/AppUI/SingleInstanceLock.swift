import Darwin
import Foundation

/// Held for the life of the process, before anything that listens globally is armed.
/// Two instances would mean two triggers and two pastes. The kernel releases it on a
/// crash, so a stale lock cannot lock the app out.
public final class SingleInstanceLock: Sendable {
    public enum Attempt {
        case acquired(SingleInstanceLock)
        case alreadyRunning
    }

    private let descriptor: Int32

    private init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        close(descriptor)
    }

    /// A volume with no `flock` proceeds without the lock, because refusing to
    /// launch there would be worse than a second instance the user started.
    public static func acquire(at url: URL) throws -> Attempt {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_EXLOCK | O_NONBLOCK, 0o600)
        if descriptor >= 0 { return .acquired(SingleInstanceLock(descriptor: descriptor)) }
        let failure = errno
        switch failure {
        case EWOULDBLOCK:
            return .alreadyRunning
        case ENOTSUP, EOPNOTSUPP:
            let plain = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
            guard plain >= 0 else { throw POSIXError(.init(rawValue: errno) ?? .EIO) }
            return .acquired(SingleInstanceLock(descriptor: plain))
        default:
            throw POSIXError(.init(rawValue: failure) ?? .EIO)
        }
    }
}
