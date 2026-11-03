import CoreFoundation
import Foundation

/// A known app that may run dictation with no knowledge of this protocol.
public struct KnownPeer: Equatable, Sendable {
    public let identifier: String
    public let preferenceKey: String

    public init(identifier: String, preferenceKey: String) {
        self.identifier = identifier
        self.preferenceKey = preferenceKey
    }
}

public struct RunningApp: Equatable, Sendable {
    public let identifier: String
    public let bundleURL: URL?

    public init(identifier: String, bundleURL: URL?) {
        self.identifier = identifier
        self.bundleURL = bundleURL
    }
}

public enum ProtocolDeclaration: Equatable, Sendable {
    case absent
    case noGlobalCapture
    case implements(version: Int)

    public static let infoKey = "DictationOwnershipProtocol"

    /// Reads the file each time, because a `Bundle` caches its dictionary for the life of the process.
    public init(bundleURL: URL?) {
        guard let plist = bundleURL?.appendingPathComponent("Contents/Info.plist"),
              let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let number = info[Self.infoKey] as? NSNumber,
              // `as? Int` would also accept a boolean or a float.
              CFGetTypeID(number) == CFNumberGetTypeID(), !CFNumberIsFloatType(number), number.intValue >= 0 else {
            self = .absent
            return
        }
        self = number.intValue == 0 ? .noGlobalCapture : .implements(version: number.intValue)
    }
}

/// Best effort, since such a peer takes no lock. It can only make a participant refuse.
public struct NonCooperatingPeers: Sendable {
    private let known: [KnownPeer]
    private let running: @Sendable () -> [RunningApp]
    private let preferenceIsOn: @Sendable (KnownPeer) -> Bool

    public init(
        known: [KnownPeer],
        running: @escaping @Sendable () -> [RunningApp],
        preferenceIsOn: @escaping @Sendable (KnownPeer) -> Bool = NonCooperatingPeers.storedPreference
    ) {
        self.known = known
        self.running = running
        self.preferenceIsOn = preferenceIsOn
    }

    public func activePeer() -> String? {
        for app in running() {
            guard let peer = known.first(where: { $0.identifier == app.identifier }),
                  ProtocolDeclaration(bundleURL: app.bundleURL) == .absent, preferenceIsOn(peer) else { continue }
            return app.identifier
        }
        return nil
    }

    /// Reads and never writes, with the same reading `UserDefaults.bool(forKey:)` gives the peer itself.
    /// Reading a domain that does not exist does not create it.
    @Sendable public static func storedPreference(of peer: KnownPeer) -> Bool {
        let domain = peer.identifier as CFString
        CFPreferencesAppSynchronize(domain)
        return CFPreferencesGetAppBooleanValue(peer.preferenceKey as CFString, domain, nil)
    }
}
