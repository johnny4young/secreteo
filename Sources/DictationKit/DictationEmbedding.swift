import Foundation
import SpeechCore

/// A saved dictation's sentence vector. Derived from its text, so it is erased with it.
public struct DictationEmbedding: Equatable, Sendable {
    public static let maximumDimension = 4_096
    public static let maximumProfileLength = 200

    public let recordID: DictationRecordID
    public let vector: [Float]

    public init(recordID: DictationRecordID, vector: [Float]) {
        self.recordID = recordID
        self.vector = vector
    }

    /// A zero vector has no direction, so no similarity can be computed from it.
    public var isValid: Bool {
        (1...Self.maximumDimension).contains(vector.count) && vector.allSatisfy(\.isFinite)
            && vector.contains { $0 != 0 }
    }
}
