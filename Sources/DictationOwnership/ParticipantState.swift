import Foundation

public enum UnavailableReason: Error, Equatable, Sendable {
    case lockUnsupported
    case newerProtocol
    case corruptState
    case ioError
    case sandboxed
    case legacyPeerActive
    case notReady(String)
}

/// What the participant knows locally. The protocol reads these and never writes them.
public struct ParticipantConditions: Equatable, Sendable {
    public var preferenceIsOn: Bool
    /// `nil` when ready. Otherwise names the missing piece.
    public var missingForReadiness: String?
    public var legacyPeerIsActive: Bool

    public init(preferenceIsOn: Bool, missingForReadiness: String?, legacyPeerIsActive: Bool) {
        self.preferenceIsOn = preferenceIsOn
        self.missingForReadiness = missingForReadiness
        self.legacyPeerIsActive = legacyPeerIsActive
    }
}

public enum ParticipantState: Equatable, Sendable {
    case off
    case preparing
    case available
    case transferring
    case owned
    case unavailable(UnavailableReason)

    public var armsTriggers: Bool { self == .owned }
    public var allowsPrewarm: Bool { self == .owned }
    public var mayOfferOwnership: Bool { self == .available }

    /// The first row of the spec's state table that matches wins, so the order here is the contract.
    public static func derive(
        participant: String,
        state: Result<OwnershipState, UnavailableReason>,
        conditions: ParticipantConditions,
        now: Date
    ) -> ParticipantState {
        let current: OwnershipState
        switch state {
        case .failure(let reason): return .unavailable(reason)
        case .success(let value): current = value
        }
        if conditions.legacyPeerIsActive { return .unavailable(.legacyPeerActive) }
        if let intent = current.intent, intent.isLive(at: now), intent.from == participant || intent.to == participant {
            return .transferring
        }
        if !conditions.preferenceIsOn { return .off }
        let isOwner = current.owner == participant
        if let missing = conditions.missingForReadiness {
            return isOwner ? .unavailable(.notReady(missing)) : .preparing
        }
        return isOwner ? .owned : .available
    }
}
