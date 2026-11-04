import Foundation

/// Strongly-typed UUID wrappers. Every persisted entity uses UUIDs (never
/// auto-increment integers) so records can sync and be shared without
/// collisions — a schema decision that must hold from v1.
public struct DictationRecordID: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: UUID
    public init(rawValue: UUID) { self.rawValue = rawValue }
    public init() { self.rawValue = UUID() }
}
