@testable import DictationOwnership
import Foundation
import Testing

private func intent(
    from: String = "com.example.app",
    to: String = "com.example.other",
    expires: String = "2026-11-03T12:00:15Z"
) -> String {
    #"{"id":"6F1E1A52-5C1B-4E58-9C49-0D0B4C2F6A11","from":"\#(from)","to":"\#(to)","createdAt":"2026-11-03T12:00:00Z","expiresAt":"\#(expires)"}"#
}

struct StateFormatTests {
    private let specExample = """
        {
          "version": 1,
          "owner": "com.example.app",
          "generation": 7,
          "previous": "com.example.other",
          "intent": {
            "id": "6F1E1A52-5C1B-4E58-9C49-0D0B4C2F6A11",
            "from": "com.example.app",
            "to": "com.example.other",
            "createdAt": "2026-11-03T12:00:00Z",
            "expiresAt": "2026-11-03T12:00:15Z"
          }
        }
        """

    @Test func aWellFormedIntentHelperIsValid() throws {
        let text = #"{"version":1,"owner":null,"generation":0,"previous":null,"intent":\#(intent())}"#
        #expect(try OwnershipState.decoded(from: Data(text.utf8)).get().intent?.to == "com.example.other")
    }

    @Test func theSpecExampleDecodes() throws {
        let state = try OwnershipState.decoded(from: Data(specExample.utf8)).get()
        #expect(state.owner == "com.example.app")
        #expect(state.generation == 7)
        #expect(state.intent?.to == "com.example.other")
        #expect(state.intent.map { $0.expiresAt.timeIntervalSince($0.createdAt) } == OwnershipIntent.lifetime)
    }

    @Test func nilFieldsAreWrittenAsNull() throws {
        let data = try OwnershipState.nobody.encoded()
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in ["owner", "previous", "intent"] {
            #expect(object[key] is NSNull, "\(key) must be present and null")
        }
    }

    @Test func anIntentFromNobodyRoundTrips() throws {
        let intent = OwnershipIntent(from: nil, to: ownerID, now: Date(timeIntervalSince1970: 1_800_000_000))
        let state = OwnershipState(owner: nil, generation: 0, previous: nil, intent: intent)
        let decoded = try OwnershipState.decoded(from: state.encoded()).get()
        #expect(decoded == state)
    }

    @Test(arguments: [
        "", "not json", "{}", "[]",
        #"{"version":1}"#,
        #"{"version":"1","owner":null,"generation":0,"previous":null,"intent":null}"#,
        #"{"version":1,"owner":null,"previous":null,"intent":null}"#,
        #"{"version":1,"owner":null,"generation":-1,"previous":null,"intent":null}"#,
        #"{"version":1,"owner":null,"generation":0,"previous":null,"intent":{"id":"x"}}"#,
        #"{"version":1,"owner":"","generation":0,"previous":null,"intent":null}"#,
        #"{"version":1,"owner":null,"generation":0,"previous":null,"intent":\#(intent(to: ""))}"#,
        #"{"version":1,"owner":null,"generation":0,"previous":null,"intent":\#(intent(from: ""))}"#,
        #"{"version":1,"owner":null,"generation":0,"previous":null,"intent":\#(intent(expires: "2026-11-03T12:00:00Z"))}"#,
        #"{"version":1,"owner":null,"generation":0,"previous":null,"intent":\#(intent(expires: "2026-11-03T13:00:00Z"))}"#
    ])
    func invalidContentIsCorrupt(text: String) {
        #expect(throws: UnavailableReason.corruptState) { try OwnershipState.decoded(from: Data(text.utf8)).get() }
    }

    @Test(arguments: [0, 2, 99])
    func aVersionItDoesNotKnowIsNotCorrupt(version: Int) {
        let text = #"{"version":\#(version),"something":"new"}"#
        #expect(throws: UnavailableReason.newerProtocol) { try OwnershipState.decoded(from: Data(text.utf8)).get() }
    }

    @Test func anIntentIsLiveOnlyUntilItExpires() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: start)
        #expect(intent.isLive(at: start))
        #expect(intent.isLive(at: start.addingTimeInterval(OwnershipIntent.lifetime - 1)))
        #expect(!intent.isLive(at: start.addingTimeInterval(OwnershipIntent.lifetime)))
    }

    @Test func aClockMovedFarBackCannotPinAnIntent() {
        let start = Date(timeIntervalSince1970: 1_800_000_000)
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: start)
        #expect(!intent.isLive(at: start.addingTimeInterval(-1)))
    }

    @Test func aNewIntentIsLiveAtAnyFractionOfASecond() {
        let start = Date(timeIntervalSince1970: 1_800_000_000.75)
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: start)
        #expect(intent.createdAt.timeIntervalSince1970 == 1_800_000_000)
        #expect(intent.isLive(at: start))
    }
}

struct StateTableTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func derive(
        _ state: Result<OwnershipState, UnavailableReason>,
        preference: Bool = true,
        missing: String? = nil,
        legacy: Bool = false
    ) -> ParticipantState {
        .derive(
            participant: ownerID,
            state: state,
            conditions: ParticipantConditions(
                preferenceIsOn: preference, missingForReadiness: missing, legacyPeerIsActive: legacy),
            now: now)
    }

    private func owned(by owner: String?, intent: OwnershipIntent? = nil) -> Result<OwnershipState, UnavailableReason> {
        .success(OwnershipState(owner: owner, generation: 1, previous: nil, intent: intent))
    }

    @Test(arguments: [
        UnavailableReason.lockUnsupported, .newerProtocol, .corruptState, .ioError, .sandboxed
    ])
    func row1FileProblemsWinOverEverything(reason: UnavailableReason) {
        #expect(derive(.failure(reason), preference: false, legacy: true) == .unavailable(reason))
    }

    @Test func row2ALegacyPeerWinsOverAnIntentAndTheOwner() {
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: now)
        #expect(derive(owned(by: ownerID, intent: intent), legacy: true) == .unavailable(.legacyPeerActive))
    }

    @Test func row3ALiveIntentNamingThisParticipantWinsOverOff() {
        let from = OwnershipIntent(from: ownerID, to: otherID, now: now)
        let to = OwnershipIntent(from: otherID, to: ownerID, now: now)
        #expect(derive(owned(by: ownerID, intent: from), preference: false) == .transferring)
        #expect(derive(owned(by: otherID, intent: to)) == .transferring)
    }

    @Test func row3IgnoresAnIntentBetweenOtherParticipants() {
        let intent = OwnershipIntent(from: otherID, to: "com.example.third", now: now)
        #expect(derive(owned(by: otherID, intent: intent)) == .available)
    }

    @Test func row3IgnoresAnExpiredIntent() {
        let intent = OwnershipIntent(from: ownerID, to: otherID, now: now.addingTimeInterval(-60))
        #expect(derive(owned(by: ownerID, intent: intent)) == .owned)
    }

    @Test func row4PreferenceOffEvenForTheOwner() {
        #expect(derive(owned(by: ownerID), preference: false) == .off)
        #expect(derive(owned(by: otherID), preference: false) == .off)
    }

    @Test func rows5And6TheOwner() {
        #expect(derive(owned(by: ownerID), missing: "microphone") == .unavailable(.notReady("microphone")))
        #expect(derive(owned(by: ownerID)) == .owned)
    }

    @Test func rows7And8NotTheOwner() {
        #expect(derive(owned(by: otherID), missing: "engine") == .preparing)
        #expect(derive(owned(by: otherID)) == .available)
        #expect(derive(owned(by: nil)) == .available)
    }

    @Test func onlyOwnedArmsAndPrewarmsAndOnlyAvailableOffers() {
        let states: [ParticipantState] = [.off, .preparing, .available, .transferring, .owned, .unavailable(.ioError)]
        #expect(states.filter(\.armsTriggers) == [.owned])
        #expect(states.filter(\.allowsPrewarm) == [.owned])
        #expect(states.filter(\.mayOfferOwnership) == [.available])
    }
}
