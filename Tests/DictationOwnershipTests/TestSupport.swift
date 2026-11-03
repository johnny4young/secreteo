@testable import DictationOwnership
import Foundation
import Synchronization
import Testing

let ownerID = "com.example.owner"
let otherID = "com.example.other"

extension ParticipantConditions {
    static let ready = ParticipantConditions(preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: false)
}

/// Lets a test change what a participant reports, and the time it sees, while it runs.
final class Conditions: Sendable {
    private let value = Mutex(ParticipantConditions.ready)
    private let time = Mutex(Date(timeIntervalSince1970: 1_800_000_000))

    var current: ParticipantConditions {
        get { value.withLock { $0 } }
        set { value.withLock { $0 = newValue } }
    }

    var now: Date {
        get { time.withLock { $0 } }
        set { time.withLock { $0 = newValue } }
    }
}

/// A scratch folder for one test. Never the real one.
struct Scratch {
    let root: URL
    let conditions = Conditions()
    var files: OwnershipFiles { OwnershipFiles(root: root) }
    var log: URL { root.deletingLastPathComponent().appendingPathComponent("events.log") }

    init() throws {
        let parent = FileManager.default.temporaryDirectory
            .appendingPathComponent("dictation-ownership-\(UUID().uuidString)", isDirectory: true)
        root = parent.appendingPathComponent("store", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root.deletingLastPathComponent())
    }

    func participant(_ id: String = ownerID, isSandboxed: Bool = false) -> DictationOwnership {
        let conditions = conditions
        return DictationOwnership(
            participant: id,
            root: root,
            isSandboxed: isSandboxed,
            conditions: { conditions.current },
            now: { conditions.now })
    }

    func seed(_ state: OwnershipState) throws {
        #expect(files.write(state))
    }

    func seedOwner(_ id: String = ownerID, generation: Int = 1) throws {
        try seed(OwnershipState(owner: id, generation: generation, previous: nil, intent: nil))
    }

    func client(_ command: String, participant: String, extra: [String] = []) throws -> Process {
        let process = Process()
        process.executableURL = try clientExecutable()
        process.arguments = [command, "--root", root.path, "--participant", participant, "--log", log.path] + extra
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// Starts a client that holds a lease, and returns once it has one.
    func holdingClient(participant: String) throws -> Process {
        let process = Process()
        let output = Pipe()
        process.executableURL = try clientExecutable()
        process.arguments = ["hold", "--root", root.path, "--participant", participant]
        process.standardOutput = output
        try process.run()
        let line = String(decoding: output.fileHandleForReading.availableData, as: UTF8.self)
        #expect(line.contains("held"))
        return process
    }

    func events() throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}

/// Counts `enter` lines that land while another process's session is open.
func overlaps(in events: [String]) -> Int {
    var open = 0
    var found = 0
    for event in events {
        if event.hasPrefix("enter") {
            if open > 0 { found += 1 }
            open += 1
        } else if event.hasPrefix("exit") {
            open -= 1
        }
    }
    return found
}

func lease(from admission: Admission, sourceLocation: SourceLocation = #_sourceLocation) -> OwnershipLease? {
    if case .admitted(let lease) = admission { return lease }
    Issue.record("Expected a lease, got \(admission)", sourceLocation: sourceLocation)
    return nil
}

func refusal(from admission: Admission) -> AdmissionRefusal? {
    if case .refused(let refusal) = admission { return refusal }
    return nil
}

private final class BundleAnchor {}

private func clientExecutable() throws -> URL {
    let products = Bundle(for: BundleAnchor.self).bundleURL.deletingLastPathComponent()
    let url = products.appendingPathComponent("ownership-test-client")
    try #require(FileManager.default.isExecutableFile(atPath: url.path), "missing \(url.path)")
    return url
}

func finish(_ process: Process) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        DispatchQueue.global().async {
            process.waitUntilExit()
            continuation.resume()
        }
    }
}
