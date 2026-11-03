import Darwin
import Foundation
import Synchronization

/// One lock on one open file description.
final class HeldLock: Sendable {
    private let descriptor: Mutex<Int32?>
    private let url: URL

    fileprivate init(descriptor: Int32, url: URL) {
        self.descriptor = Mutex(descriptor)
        self.url = url
    }

    deinit {
        release()
    }

    func release() {
        descriptor.withLock { value in
            // Close alone is not enough: a child being spawned holds the description until its exec.
            if let open = value {
                flock(open, LOCK_UN)
                close(open)
            }
            value = nil
        }
    }

    /// For tests that need a second reference to the open file description.
    var descriptorForTesting: Int32? {
        descriptor.withLock { $0 }
    }

    /// False once released, or when the path no longer names the locked file.
    var namesCurrentFile: Bool {
        descriptor.withLock { value in
            guard let open = value else { return false }
            var held = stat()
            var current = stat()
            guard fstat(open, &held) == 0, stat(url.path, &current) == 0 else { return false }
            return held.st_dev == current.st_dev && held.st_ino == current.st_ino
        }
    }
}

enum LockAttempt {
    case held(HeldLock)
    case busy
    case failed(UnavailableReason)
}

struct OwnershipFiles: Sendable {
    static let maximumStateSize = 64 * 1024

    let root: URL

    var captureLock: URL { root.appendingPathComponent("capture.lock") }
    var stateLock: URL { root.appendingPathComponent("state.lock") }
    var stateFile: URL { root.appendingPathComponent("ownership.json") }

    func prepareDirectory() -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return false
        }
        var info = stat()
        guard stat(root.path, &info) == 0 else { return false }
        if info.st_mode & 0o077 != 0, chmod(root.path, 0o700) != 0 { return false }
        excludeFromBackups()
        return true
    }

    // Best effort: a restore bringing back an old owner is not worth refusing a session.
    private func excludeFromBackups() {
        guard (try? root.resourceValues(forKeys: [.isExcludedFromBackupKey]))?.isExcludedFromBackup != true else {
            return
        }
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var folder = root
        try? folder.setResourceValues(values)
    }

    /// Finds access problems without holding the lock, so a refresh cannot make a key press refuse `busy`.
    func canOpen(_ url: URL) -> Bool {
        let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return false }
        close(descriptor)
        return true
    }

    /// Opens a new descriptor every time: `flock` would not conflict with one already holding the lock.
    /// `beforeIdentityCheck` lets a test replace the file at the only moment this check can catch it.
    func tryLock(_ url: URL, beforeIdentityCheck: (() -> Void)? = nil) -> LockAttempt {
        for _ in 0..<2 {
            let descriptor = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
            guard descriptor >= 0 else { return .failed(.ioError) }
            guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
                let failure = errno
                close(descriptor)
                return Self.attempt(forFlockError: failure)
            }
            let lock = HeldLock(descriptor: descriptor, url: url)
            beforeIdentityCheck?()
            if lock.namesCurrentFile { return .held(lock) }
            lock.release()
        }
        return .failed(.ioError)
    }

    static func attempt(forFlockError failure: Int32) -> LockAttempt {
        switch failure {
        case EWOULDBLOCK: .busy
        case ENOTSUP, EOPNOTSUPP: .failed(.lockUnsupported)
        default: .failed(.ioError)
        }
    }

    /// Needs no lock, because a write replaces the whole file through a rename.
    func read() -> Result<OwnershipState, UnavailableReason> {
        let descriptor = open(stateFile.path, O_RDONLY | O_CLOEXEC)
        guard descriptor >= 0 else { return errno == ENOENT ? .success(.nobody) : .failure(.ioError) }
        defer { close(descriptor) }
        var buffer = [UInt8](repeating: 0, count: Self.maximumStateSize + 1)
        var total = 0
        while total < buffer.count {
            let count = buffer.withUnsafeMutableBytes { bytes in
                Darwin.read(descriptor, bytes.baseAddress! + total, bytes.count - total)
            }
            if count < 0 && errno == EINTR { continue }
            guard count >= 0 else { return .failure(.ioError) }
            if count == 0 { break }
            total += count
        }
        guard total <= Self.maximumStateSize else { return .failure(.corruptState) }
        return OwnershipState.decoded(from: Data(buffer[..<total]))
    }

    /// The caller holds the state lock, so any temporary file found here is a dead writer's.
    func write(_ state: OwnershipState, flush: (Int32) -> Bool = { Self.flush($0) }) -> Bool {
        removeStaleTemporaries()
        guard let data = try? state.encoded() else { return false }
        let temporary = root.appendingPathComponent("ownership.json.\(UUID().uuidString).tmp")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return false }
        let flushed = writeAll(data, to: descriptor) && flush(descriptor)
        close(descriptor)
        guard flushed, rename(temporary.path, stateFile.path) == 0 else {
            unlink(temporary.path)
            return false
        }
        return true
    }

    /// Not every volume supports `F_FULLFSYNC`.
    static func flush(_ descriptor: Int32, fullSync: (Int32) -> Int32 = { fcntl($0, F_FULLFSYNC) }) -> Bool {
        fullSync(descriptor) == 0 || fsync(descriptor) == 0
    }

    private func writeAll(_ data: Data, to descriptor: Int32) -> Bool {
        data.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let written = Darwin.write(descriptor, buffer.baseAddress! + offset, buffer.count - offset)
                if written < 0 && errno == EINTR { continue }
                guard written > 0 else { return false }
                offset += written
            }
            return true
        }
    }

    private func removeStaleTemporaries() {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        for name in names where name.hasPrefix("ownership.json.") && name.hasSuffix(".tmp") {
            unlink(root.appendingPathComponent(name).path)
        }
    }
}
