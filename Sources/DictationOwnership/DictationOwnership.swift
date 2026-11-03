import Foundation
import Synchronization

public enum LeaseKind: Equatable, Sendable {
    case global
    /// Open to a participant that is not the owner or not ready yet. Never delivers outside its own window.
    case practice
}

public enum AdmissionRefusal: Error, Equatable, Sendable {
    case busy
    case transferring
    case notOwner(String?)
    case off
    case unavailable(UnavailableReason)
}

public enum Admission: Sendable {
    case admitted(OwnershipLease)
    case refused(AdmissionRefusal)
}

/// The capture lock, held for one operation until delivery has finished and Stop has drained.
public final class OwnershipLease: Sendable {
    public let kind: LeaseKind
    public let owner: String?
    public let generation: Int
    private let lock: HeldLock
    private let files: OwnershipFiles

    fileprivate init(kind: LeaseKind, state: OwnershipState, lock: HeldLock, files: OwnershipFiles) {
        self.kind = kind
        owner = state.owner
        generation = state.generation
        self.lock = lock
        self.files = files
    }

    /// Call immediately before delivering. On false, keep the text and do not paste.
    public func revalidate() -> Bool {
        guard lock.namesCurrentFile, case .success(let state) = files.read() else { return false }
        return state.owner == owner && state.generation == generation
    }

    public func release() {
        lock.release()
    }
}

/// One participant's view of the protocol in `docs/specs/ownership-protocol.md`.
public final class DictationOwnership: Sendable {
    public static let folderName = "com.johnny4young.dictation-ownership"
    public static let notificationName = "com.johnny4young.dictation-ownership.changed"

    public let participant: String
    let files: OwnershipFiles
    private let isSandboxed: Bool
    let conditions: @Sendable () -> ParticipantConditions
    let now: @Sendable () -> Date
    let changeNotificationName: String
    let timings: OwnershipTimings

    /// The default folder, which is not usable from a sandboxed process.
    public static var defaultRoot: URL {
        accountHome
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    // From the account, because Foundation's home directory follows `CFFIXED_USER_HOME`.
    private static var accountHome: URL {
        var entry = passwd()
        var result: UnsafeMutablePointer<passwd>?
        var buffer = [CChar](repeating: 0, count: 16_384)
        guard getpwuid_r(getuid(), &entry, &buffer, buffer.count, &result) == 0, result != nil,
              let directory = entry.pw_dir else {
            // Nothing can be created here, so this fails closed as `ioError`.
            return URL(fileURLWithPath: "/var/empty", isDirectory: true)
        }
        return URL(fileURLWithPath: String(cString: directory), isDirectory: true)
    }

    /// `root` and `notificationName` are parameters so tests stay scratch, and nothing else may move them.
    public init(
        participant: String,
        root: URL = DictationOwnership.defaultRoot,
        isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
        conditions: @escaping @Sendable () -> ParticipantConditions,
        now: @escaping @Sendable () -> Date = { Date() },
        notificationName: String = DictationOwnership.notificationName,
        timings: OwnershipTimings = .standard
    ) {
        self.participant = participant
        files = OwnershipFiles(root: root)
        self.isSandboxed = isSandboxed
        self.conditions = conditions
        self.now = now
        changeNotificationName = notificationName
        self.timings = timings
    }

    public func status() -> ParticipantState {
        if let reason = setupFailure() { return .unavailable(reason) }
        guard files.canOpen(files.captureLock) else { return .unavailable(.ioError) }
        // The state lock, because a writer waits for it and a key press would not wait for capture.
        switch files.tryLock(files.stateLock) {
        case .held(let probe): probe.release()
        case .busy: break
        case .failed(let reason): return .unavailable(reason)
        }
        return .derive(participant: participant, state: files.read(), conditions: conditions(), now: now())
    }

    /// Never waits, and does file I/O, so it never runs in an audio or event tap callback.
    public func acquire(_ kind: LeaseKind) -> Admission {
        if let reason = setupFailure() { return .refused(.unavailable(reason)) }
        let lock: HeldLock
        switch files.tryLock(files.captureLock) {
        case .held(let held): lock = held
        case .busy: return .refused(.busy)
        case .failed(let reason): return .refused(.unavailable(reason))
        }
        switch admit(kind) {
        case .success(let state):
            return .admitted(OwnershipLease(kind: kind, state: state, lock: lock, files: files))
        case .failure(let refusal):
            lock.release()
            return .refused(refusal)
        }
    }

    private func setupFailure() -> UnavailableReason? {
        if isSandboxed { return .sandboxed }
        return files.prepareDirectory() ? nil : .ioError
    }

    private func admit(_ kind: LeaseKind) -> Result<OwnershipState, AdmissionRefusal> {
        let state: OwnershipState
        switch files.read() {
        case .failure(let reason): return .failure(.unavailable(reason))
        case .success(let value): state = value
        }
        if let intent = state.intent, intent.isLive(at: now()) { return .failure(.transferring) }
        guard kind == .global else { return .success(state) }
        guard state.owner == participant else { return .failure(.notOwner(state.owner)) }

        let current = conditions()
        if current.legacyPeerIsActive { return .failure(.unavailable(.legacyPeerActive)) }
        if !current.preferenceIsOn { return .failure(.off) }
        if let missing = current.missingForReadiness { return .failure(.unavailable(.notReady(missing))) }
        return .success(state)
    }
}

/// Ties each Stop to its own start, so the release after a refused press cannot reach another session.
public final class SessionAttempts: Sendable {
    public struct Token: Hashable, Sendable {
        fileprivate let id = UUID()
    }

    private let ownership: DictationOwnership
    private let leases = Mutex<[Token: OwnershipLease]>([:])

    public init(ownership: DictationOwnership) {
        self.ownership = ownership
    }

    public func start(_ kind: LeaseKind) -> (token: Token, admission: Admission) {
        let token = Token()
        let admission = ownership.acquire(kind)
        if case .admitted(let lease) = admission {
            leases.withLock { $0[token] = lease }
        }
        return (token, admission)
    }

    /// The lease this attempt received, or `nil` for a refused or finished one, whose Stop does nothing.
    public func lease(for token: Token) -> OwnershipLease? {
        leases.withLock { $0[token] }
    }

    /// Releases the lease. Call it after delivery has finished and Stop has drained, not on the Stop itself.
    @discardableResult
    public func finish(_ token: Token) -> Bool {
        guard let lease = leases.withLock({ $0.removeValue(forKey: token) }) else { return false }
        lease.release()
        return true
    }
}
