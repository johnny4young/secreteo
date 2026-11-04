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
        try #require(files.write(state))
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

    func clientOutput(_ arguments: [String], environment: [String: String]) throws -> String {
        let process = Process()
        let output = Pipe()
        process.executableURL = try clientExecutable()
        process.arguments = arguments
        process.environment = environment
        process.standardOutput = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        while process.isRunning { usleep(1_000) }
        return String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func events() throws -> [String] {
        try String(contentsOf: log, encoding: .utf8).split(separator: "\n").map(String.init)
    }
}

/// Every way a log can break exclusion: an `enter` during another session, an `exit` with no
/// matching `enter`, or a session that never ended.
func violations(in events: [String]) -> [String] {
    var open = Set<String>()
    var found: [String] = []
    for event in events {
        let parts = event.split(separator: " ").map(String.init)
        guard parts.count == 2 else {
            found.append("malformed: \(event)")
            continue
        }
        if parts[0] == "enter" {
            if !open.isEmpty { found.append("overlap: \(event)") }
            open.insert(parts[1])
        } else if parts[0] == "exit", open.remove(parts[1]) == nil {
            found.append("unmatched: \(event)")
        }
    }
    return found + open.map { "unfinished: \($0)" }
}

/// Each log line a process wrote, keyed by the process that wrote it.
func attempts(in events: [String], by process: Process) -> Int {
    events.filter { $0.hasSuffix(" \(process.processIdentifier)") && !$0.hasPrefix("exit") }.count
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

/// Polls because `waitUntilExit` on a worker thread once hung with no child left.
func finish(_ process: Process) async {
    while process.isRunning {
        try? await Task.sleep(for: .milliseconds(5))
    }
}

func finishClean(_ process: Process, sourceLocation: SourceLocation = #_sourceLocation) async {
    await finish(process)
    #expect(process.terminationStatus == 0, sourceLocation: sourceLocation)
}
