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

    public let participant: String
    let files: OwnershipFiles
    private let isSandboxed: Bool
    private let conditions: @Sendable () -> ParticipantConditions
    let now: @Sendable () -> Date

    /// The default folder, which is not usable from a sandboxed process.
    public static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support", isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    /// `root` is a parameter so tests can use a scratch folder, and nothing else may move it.
    public init(
        participant: String,
        root: URL = DictationOwnership.defaultRoot,
        isSandboxed: Bool = ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil,
        conditions: @escaping @Sendable () -> ParticipantConditions,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.participant = participant
        files = OwnershipFiles(root: root)
        self.isSandboxed = isSandboxed
        self.conditions = conditions
        self.now = now
    }

    public func status() -> ParticipantState {
        if let reason = setupFailure() { return .unavailable(reason) }
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

/// Ties each Stop to its own start, so the release after a refused press cannot end another session.
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

    /// Returns whether this ended a lease. A token from a refused start ends nothing.
    @discardableResult
    public func stop(_ token: Token) -> Bool {
        guard let lease = leases.withLock({ $0.removeValue(forKey: token) }) else { return false }
        lease.release()
        return true
    }
}
