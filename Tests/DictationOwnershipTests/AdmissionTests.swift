import Darwin
@testable import DictationOwnership
import Foundation
import Testing

struct AdmissionTests {
    private func withScratch(_ body: (Scratch) throws -> Void) throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try body(scratch)
    }

    @Test func theOwnerIsAdmittedAtTheCurrentGeneration() throws {
        try withScratch { scratch in
            try scratch.seedOwner(generation: 7)
            let held = lease(from: scratch.participant().acquire(.global))
            #expect(held?.owner == ownerID)
            #expect(held?.generation == 7)
            #expect(held?.revalidate() == true)
        }
    }

    @Test func nobodyIsAdmittedWithNoStateFile() throws {
        try withScratch { scratch in
            #expect(refusal(from: scratch.participant().acquire(.global)) == .notOwner(nil))
            #expect(!FileManager.default.fileExists(atPath: scratch.files.stateFile.path))
        }
    }

    @Test func anotherParticipantIsRefusedAndNamesTheOwner() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            #expect(refusal(from: scratch.participant(otherID).acquire(.global)) == .notOwner(ownerID))
        }
    }

    @Test func aSecondAcquireInOneProcessIsBusyWhileTheFirstStaysValid() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            let ownership = scratch.participant()
            let first = lease(from: ownership.acquire(.global))
            #expect(refusal(from: ownership.acquire(.global)) == .busy)
            #expect(first?.revalidate() == true)
            first?.release()
            #expect(lease(from: ownership.acquire(.global)) != nil)
        }
    }

    @Test func aRefusalLeavesTheLockFree() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            #expect(refusal(from: scratch.participant(otherID).acquire(.global)) == .notOwner(ownerID))
            #expect(lease(from: scratch.participant().acquire(.global)) != nil)
        }
    }

    @Test func aReleasedLeaseIsNoLongerValid() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            let held = lease(from: scratch.participant().acquire(.global))
            held?.release()
            #expect(held?.revalidate() == false)
        }
    }

    @Test func aStateChangedBehindALeaseFailsRevalidation() throws {
        try withScratch { scratch in
            try scratch.seedOwner(generation: 2)
            let held = lease(from: scratch.participant().acquire(.global))
            try scratch.seedOwner(generation: 3)
            #expect(held?.revalidate() == false)
            try scratch.seedOwner(otherID, generation: 2)
            #expect(held?.revalidate() == false)
            try Data("{".utf8).write(to: scratch.files.stateFile)
            #expect(held?.revalidate() == false)
        }
    }

    @Test func aLiveIntentRefusesBothKinds() throws {
        try withScratch { scratch in
            let intent = OwnershipIntent(from: ownerID, to: otherID, now: scratch.conditions.now)
            try scratch.seed(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent))
            #expect(refusal(from: scratch.participant().acquire(.global)) == .transferring)
            #expect(refusal(from: scratch.participant(otherID).acquire(.practice)) == .transferring)
        }
    }

    @Test func anExpiredIntentNoLongerRefuses() throws {
        try withScratch { scratch in
            let intent = OwnershipIntent(from: ownerID, to: otherID, now: scratch.conditions.now)
            try scratch.seed(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: intent))
            scratch.conditions.now = intent.expiresAt
            #expect(lease(from: scratch.participant().acquire(.global)) != nil)
        }
    }

    @Test func revokedPermissionRefusesWithItsReasonAndKeepsTheOwner() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            scratch.conditions.current.missingForReadiness = "accessibility"
            let ownership = scratch.participant()
            #expect(refusal(from: ownership.acquire(.global)) == .unavailable(.notReady("accessibility")))
            #expect(ownership.status() == .unavailable(.notReady("accessibility")))
            #expect(scratch.files.read() == .success(OwnershipState(owner: ownerID, generation: 1, previous: nil, intent: nil)))
        }
    }

    @Test func aMissingEngineRefusesTheSameWay() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            scratch.conditions.current.missingForReadiness = "engine"
            #expect(refusal(from: scratch.participant().acquire(.global)) == .unavailable(.notReady("engine")))
        }
    }

    @Test func preferenceOffRefusesTheOwnerAndDoesNotWrite() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            let before = try Data(contentsOf: scratch.files.stateFile)
            scratch.conditions.current.preferenceIsOn = false
            let ownership = scratch.participant()
            #expect(refusal(from: ownership.acquire(.global)) == .off)
            #expect(ownership.status() == .off)
            #expect(try Data(contentsOf: scratch.files.stateFile) == before)
        }
    }

    @Test func aLegacyPeerRefusesGlobalAndAllowsPractice() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            scratch.conditions.current.legacyPeerIsActive = true
            let ownership = scratch.participant()
            #expect(refusal(from: ownership.acquire(.global)) == .unavailable(.legacyPeerActive))
            #expect(lease(from: ownership.acquire(.practice)) != nil)
        }
    }

    @Test func practiceIsOpenToANonOwnerThatIsNotReady() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            scratch.conditions.current = ParticipantConditions(
                preferenceIsOn: false, missingForReadiness: "practice", legacyPeerIsActive: false)
            let held = lease(from: scratch.participant(otherID).acquire(.practice))
            #expect(held?.kind == .practice)
        }
    }

    @Test func practiceAndGlobalCompeteForCapture() throws {
        try withScratch { scratch in
            try scratch.seedOwner()
            let practice = lease(from: scratch.participant(otherID).acquire(.practice))
            #expect(refusal(from: scratch.participant().acquire(.global)) == .busy)
            practice?.release()
            #expect(lease(from: scratch.participant().acquire(.global)) != nil)
        }
    }

    @Test func aHigherVersionFailsClosedAndLeavesTheFileByteIdentical() throws {
        try withScratch { scratch in
            let future = Data(#"{"version":2,"owner":"com.example.owner","whatever":true}"#.utf8)
            try future.write(to: scratch.files.stateFile)
            let ownership = scratch.participant()
            #expect(ownership.status() == .unavailable(.newerProtocol))
            #expect(refusal(from: ownership.acquire(.global)) == .unavailable(.newerProtocol))
            #expect(refusal(from: ownership.acquire(.practice)) == .unavailable(.newerProtocol))
            #expect(try Data(contentsOf: scratch.files.stateFile) == future)
        }
    }

    @Test func corruptStateIsRefusedAndLeftInPlace() throws {
        try withScratch { scratch in
            let garbage = Data("{".utf8)
            try garbage.write(to: scratch.files.stateFile)
            let ownership = scratch.participant()
            #expect(ownership.status() == .unavailable(.corruptState))
            #expect(refusal(from: ownership.acquire(.global)) == .unavailable(.corruptState))
            #expect(try Data(contentsOf: scratch.files.stateFile) == garbage)
        }
    }

    @Test func aReadFailureIsAnIOErrorAndNotCorruption() throws {
        try withScratch { scratch in
            try FileManager.default.createDirectory(at: scratch.files.stateFile, withIntermediateDirectories: false)
            #expect(scratch.participant().status() == .unavailable(.ioError))
        }
    }

    @Test func aSandboxedProcessCreatesNothing() throws {
        try withScratch { scratch in
            let unused = scratch.root.appendingPathComponent("container", isDirectory: true)
            let ownership = DictationOwnership(
                participant: ownerID, root: unused, isSandboxed: true, conditions: { .ready })
            #expect(ownership.status() == .unavailable(.sandboxed))
            #expect(refusal(from: ownership.acquire(.global)) == .unavailable(.sandboxed))
            #expect(!FileManager.default.fileExists(atPath: unused.path))
        }
    }

    @Test func theFolderIsPrivateAndOutOfBackups() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let root = scratch.root.appendingPathComponent("fresh", isDirectory: true)
        _ = DictationOwnership(participant: ownerID, root: root, isSandboxed: false, conditions: { .ready }).status()
        let attributes = try FileManager.default.attributesOfItem(atPath: root.path)
        #expect(attributes[.posixPermissions] as? Int == 0o700)
        #expect(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup == true)
    }
}

struct LockFileTests {
    @Test func aFileReplacedBetweenOpenAndLockIsDetectedAndRetried() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let path = scratch.files.captureLock
        var replaced = false
        let attempt = scratch.files.tryLock(path, beforeIdentityCheck: {
            guard !replaced else { return }
            replaced = true
            unlink(path.path)
            FileManager.default.createFile(atPath: path.path, contents: nil)
        })
        guard case .held(let lock) = attempt else {
            Issue.record("The retry must land on the new file")
            return
        }
        #expect(replaced)
        #expect(lock.namesCurrentFile)
    }

    @Test func aFileThatKeepsBeingReplacedIsAnIOError() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let path = scratch.files.captureLock
        let attempt = scratch.files.tryLock(path, beforeIdentityCheck: {
            unlink(path.path)
            FileManager.default.createFile(atPath: path.path, contents: nil)
        })
        guard case .failed(.ioError) = attempt else {
            Issue.record("Expected ioError, got \(attempt)")
            return
        }
    }

    @Test func anOlderHolderCannotDeliverAfterItsFileIsReplaced() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let held = lease(from: scratch.participant().acquire(.global))
        unlink(scratch.files.captureLock.path)
        #expect(held?.revalidate() == false)
    }

    @Test func aSymlinkIsRefused() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let target = scratch.root.appendingPathComponent("elsewhere")
        FileManager.default.createFile(atPath: target.path, contents: nil)
        try FileManager.default.createSymbolicLink(at: scratch.files.captureLock, withDestinationURL: target)
        guard case .failed(.ioError) = scratch.files.tryLock(scratch.files.captureLock) else {
            Issue.record("A symlink must not be followed")
            return
        }
    }

    @Test func flockErrorsMapToTheSpecReasons() {
        guard case .busy = OwnershipFiles.attempt(forFlockError: EWOULDBLOCK) else {
            Issue.record("EWOULDBLOCK means held")
            return
        }
        for failure in [ENOTSUP, EOPNOTSUPP] {
            guard case .failed(.lockUnsupported) = OwnershipFiles.attempt(forFlockError: failure) else {
                Issue.record("\(failure) has to fail closed")
                return
            }
        }
        guard case .failed(.ioError) = OwnershipFiles.attempt(forFlockError: EIO) else {
            Issue.record("Anything else is an I/O error")
            return
        }
    }

    @Test func aWriteLeavesNoTemporaryFileAndClearsAStaleOne() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let stale = scratch.root.appendingPathComponent("ownership.json.dead.tmp")
        FileManager.default.createFile(atPath: stale.path, contents: Data("{".utf8))
        try scratch.seedOwner()
        let names = try FileManager.default.contentsOfDirectory(atPath: scratch.root.path)
        #expect(names == ["ownership.json"])
    }

    @Test func aFailedWriteKeepsTheOldState() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 3)
        chmod(scratch.root.path, 0o500)
        defer { chmod(scratch.root.path, 0o700) }
        #expect(!scratch.files.write(OwnershipState(owner: otherID, generation: 4, previous: nil, intent: nil)))
        #expect(scratch.files.read() == .success(OwnershipState(owner: ownerID, generation: 3, previous: nil, intent: nil)))
    }
}

struct LockReleaseTests {
    // A child being spawned holds the description until its exec, so closing alone would not release it yet.
    @Test func aReleaseFreesTheLockAtOnceWhileChildrenAreSpawned() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let ownership = scratch.participant()
        let spawner = Task.detached {
            while !Task.isCancelled {
                let child = Process()
                child.executableURL = URL(fileURLWithPath: "/usr/bin/true")
                try? child.run()
                child.waitUntilExit()
            }
        }
        defer { spawner.cancel() }
        var refused = 0
        for _ in 0..<2_000 {
            guard case .admitted(let held) = ownership.acquire(.global) else {
                refused += 1
                continue
            }
            held.release()
        }
        #expect(refused == 0)
    }
}

struct SessionAttemptsTests {
    @Test func theReleaseAfterARefusedPressCannotEndAnotherSession() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let attempts = SessionAttempts(ownership: scratch.participant())

        let menu = attempts.start(.global)
        let press = attempts.start(.global)
        #expect(refusal(from: press.admission) == .busy)
        #expect(!attempts.stop(press.token))
        // The menu session still holds the lock, so a new attempt is still busy.
        #expect(refusal(from: attempts.start(.global).admission) == .busy)

        #expect(attempts.stop(menu.token))
        #expect(lease(from: attempts.start(.global).admission) != nil)
    }

    @Test func aSecondStopDoesNothing() throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let attempts = SessionAttempts(ownership: scratch.participant())
        let session = attempts.start(.global)
        #expect(attempts.stop(session.token))
        #expect(!attempts.stop(session.token))
    }
}

struct MultiprocessTests {
    @Test func theNegativeControlShowsTheLogCatchesOverlaps() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        let clients = try (0..<3).map { _ in
            try scratch.client("sessions", participant: ownerID, extra: ["--rounds", "200", "--skip-lease", "--hold-us", "200"])
        }
        for client in clients { await finish(client) }
        #expect(overlaps(in: try scratch.events()) > 0, "With no lease the checker must report overlaps")
    }

    @Test func simultaneousClientsNeverOverlapAndOnlyTheOwnerEnters() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner()
        let arguments = ["--rounds", "300", "--hold-us", "200"]
        let clients = [
            try scratch.client("sessions", participant: ownerID, extra: arguments),
            try scratch.client("sessions", participant: ownerID, extra: arguments),
            try scratch.client("sessions", participant: otherID, extra: arguments),
            try scratch.client("sessions", participant: "\(ownerID).dev", extra: arguments)
        ]
        for client in clients { await finish(client) }

        let events = try scratch.events()
        #expect(overlaps(in: events) == 0)
        #expect(events.contains { $0.hasPrefix("enter") })
        #expect(events.contains { $0.hasPrefix("busy") }, "The clients have to have competed for this to prove anything")
        let enteringProcesses = Set(events.filter { $0.hasPrefix("enter") })
        let ownerProcesses = Set([clients[0], clients[1]].map { "enter \($0.processIdentifier)" })
        #expect(enteringProcesses.isSubset(of: ownerProcesses))
    }

    @Test func aKilledHolderFreesTheLockAndLeavesTheOwner() async throws {
        let scratch = try Scratch()
        defer { scratch.cleanUp() }
        try scratch.seedOwner(generation: 5)
        let before = try Data(contentsOf: scratch.files.stateFile)
        let holder = try scratch.holdingClient(participant: ownerID)
        #expect(refusal(from: scratch.participant().acquire(.global)) == .busy)

        kill(holder.processIdentifier, SIGKILL)
        await finish(holder)

        #expect(refusal(from: scratch.participant(otherID).acquire(.global)) == .notOwner(ownerID))
        #expect(try Data(contentsOf: scratch.files.stateFile) == before)
        let relaunched = lease(from: scratch.participant().acquire(.global))
        #expect(relaunched?.generation == 5)
    }
}
