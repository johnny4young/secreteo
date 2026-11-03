import Foundation

/// The contents of `ownership.json`, as `docs/specs/ownership-protocol.md` defines it.
public struct OwnershipState: Codable, Equatable, Sendable {
    public static let currentVersion = 1
    public static let nobody = OwnershipState(owner: nil, generation: 0, previous: nil, intent: nil)

    public let version: Int
    public var owner: String?
    public var generation: Int
    public var previous: String?
    public var intent: OwnershipIntent?

    public init(owner: String?, generation: Int, previous: String?, intent: OwnershipIntent?) {
        version = Self.currentVersion
        self.owner = owner
        self.generation = generation
        self.previous = previous
        self.intent = intent
    }

    private enum CodingKeys: CodingKey {
        case version, owner, generation, previous, intent
    }

    // Synthesized coding would drop a nil field, and a missing field means a corrupt file.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        owner = try container.decode(String?.self, forKey: .owner)
        generation = try container.decode(Int.self, forKey: .generation)
        previous = try container.decode(String?.self, forKey: .previous)
        intent = try container.decode(OwnershipIntent?.self, forKey: .intent)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(owner, forKey: .owner)
        try container.encode(generation, forKey: .generation)
        try container.encode(previous, forKey: .previous)
        try container.encode(intent, forKey: .intent)
    }

    /// Reads the version first, so a newer format is never reported as corrupt.
    public static func decoded(from data: Data) -> Result<OwnershipState, UnavailableReason> {
        struct VersionProbe: Decodable { let version: Int }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let probe = try? decoder.decode(VersionProbe.self, from: data) else { return .failure(.corruptState) }
        guard probe.version == currentVersion else { return .failure(.newerProtocol) }
        guard let state = try? decoder.decode(OwnershipState.self, from: data), state.isValid else {
            return .failure(.corruptState)
        }
        return .success(state)
    }

    private var isValid: Bool {
        guard generation >= 0, owner?.isEmpty != true else { return false }
        guard let intent else { return true }
        return !intent.to.isEmpty && intent.from?.isEmpty != true
            && intent.expiresAt == intent.createdAt.addingTimeInterval(OwnershipIntent.lifetime)
    }

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }
}

public struct OwnershipIntent: Codable, Equatable, Sendable {
    public static let lifetime: TimeInterval = 15

    public let id: UUID
    public let from: String?
    public let to: String
    public let createdAt: Date
    public let expiresAt: Date

    public init(id: UUID = UUID(), from: String?, to: String, now: Date) {
        self.id = id
        self.from = from
        self.to = to
        // Rounded down, so a new intent is never more than a lifetime ahead of the clock.
        createdAt = Date(timeIntervalSince1970: now.timeIntervalSince1970.rounded(.down))
        expiresAt = createdAt.addingTimeInterval(Self.lifetime)
    }

    private enum CodingKeys: CodingKey {
        case id, from, to, createdAt, expiresAt
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        from = try container.decode(String?.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(from, forKey: .from)
        try container.encode(to, forKey: .to)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(expiresAt, forKey: .expiresAt)
    }

    /// Far ahead of the clock counts as expired, so a clock moved back cannot pin an intent.
    public func isLive(at now: Date) -> Bool {
        now < expiresAt && expiresAt.timeIntervalSince(now) <= Self.lifetime
    }
}
