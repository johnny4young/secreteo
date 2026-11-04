import DictationOwnership
import Foundation
import Testing

@testable import DictationSession

@MainActor
struct KnownDictationPeersTests {
    private func peers(running identifier: String, preferenceIsOn: Bool = true) -> NonCooperatingPeers {
        NonCooperatingPeers(
            known: KnownDictationPeers.all,
            running: { [RunningApp(identifier: identifier, bundleURL: nil)] },
            preferenceIsOn: { _ in preferenceIsOn })
    }

    @Test(arguments: KnownDictationPeers.all.map(\.identifier))
    func aRunningPeerWithoutTheProtocolIsLegacy(identifier: String) {
        #expect(peers(running: identifier).activePeer() == identifier)
    }

    @Test
    func aPeerWithItsPreferenceOffIsIgnored() {
        let identifier = KnownDictationPeers.all[0].identifier

        #expect(peers(running: identifier, preferenceIsOn: false).activePeer() == nil)
    }

    @Test(arguments: ["com.johnny4young.secreteo", "com.johnny4young.secreteo.dev"])
    func aSecreteoBuildIsNeverItsOwnLegacyPeer(identifier: String) {
        #expect(peers(running: identifier).activePeer() == nil)
    }

    @Test(arguments: ["com.johnny4young.secreteo", "com.johnny4young.secreteo.dev"])
    func onlyAShippedSecreteoBuildWithARealLibraryTouchesTheRealOwner(identifier: String) {
        #expect(DictationOwnershipCoordinator.usesRealOwner(identifier: identifier, usesTemporaryStore: false))
        #expect(!DictationOwnershipCoordinator.usesRealOwner(identifier: identifier, usesTemporaryStore: true))
    }

    @Test(arguments: KnownDictationPeers.all.map(\.identifier) + ["com.johnny4young.secreteo.uitests", "com.example.other"])
    func noOtherBuildTouchesTheRealOwner(identifier: String) {
        #expect(!DictationOwnershipCoordinator.usesRealOwner(identifier: identifier, usesTemporaryStore: false))
    }
}
