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
              let value = info[Self.infoKey] as? Int, value >= 0 else {
            self = .absent
            return
        }
        self = value == 0 ? .noGlobalCapture : .implements(version: value)
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

    /// Reads and never writes. Reading a domain that does not exist does not create it.
    @Sendable public static func storedPreference(of peer: KnownPeer) -> Bool {
        let domain = peer.identifier as CFString
        CFPreferencesAppSynchronize(domain)
        return (CFPreferencesCopyAppValue(peer.preferenceKey as CFString, domain) as? Bool) ?? false
    }
}
