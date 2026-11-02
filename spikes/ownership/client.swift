import CoreFoundation
import Darwin
import Foundation

struct Ownership: Codable {
    var owner: String
    var generation: Int
}

func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: "--\(name)"),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

func flag(_ name: String) -> Bool { CommandLine.arguments.contains("--\(name)") }
func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }

let root = argument("root") ?? ""
let app = argument("app") ?? ""
let lockPath = root + "/capture.lock"
let statePath = root + "/ownership.json"

func emit(_ line: String) {
    guard let path = argument("log") else { return }
    let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
    precondition(descriptor >= 0)
    _ = line.withCString { write(descriptor, $0, strlen($0)) }
    close(descriptor)
}

func readState() -> Ownership? {
    guard let data = FileManager.default.contents(atPath: statePath) else { return nil }
    return try? JSONDecoder().decode(Ownership.self, from: data)
}

// Rename keeps a killed writer from leaving a partial state.
func publish(_ state: Ownership) throws {
    let temporary = "\(statePath).\(getpid()).tmp"
    try JSONEncoder().encode(state).write(to: URL(fileURLWithPath: temporary))
    guard rename(temporary, statePath) == 0 else { throw POSIXError(.EIO) }
}

func lockDescriptor() -> Int32 {
    let descriptor = open(lockPath, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
    precondition(descriptor >= 0)
    return descriptor
}

func acquire(timeoutMs: Int) -> Int32? {
    let descriptor = lockDescriptor()
    let deadline = now() + UInt64(timeoutMs) * 1_000_000
    repeat {
        if flag("no-lock") || flock(descriptor, LOCK_EX | LOCK_NB) == 0 { return descriptor }
        usleep(100)
    } while now() < deadline
    close(descriptor)
    return nil
}

func session(hold: UInt32) {
    let label = "\(app) \(getpid())"
    guard let descriptor = acquire(timeoutMs: 10_000) else { return }
    defer { close(descriptor) }
    guard let state = readState(), state.owner == app else {
        emit("refused \(label)\n")
        return
    }
    emit("enter \(label) \(state.generation)\n")
    usleep(hold)
    emit("exit \(label) \(state.generation)\n")
}

func toJSON(_ value: [String: Any]) -> String {
    let data = (try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])) ?? Data()
    return String(decoding: data, as: UTF8.self)
}

switch CommandLine.arguments.dropFirst().first {
case "init":
    try FileManager.default.createDirectory(atPath: root, withIntermediateDirectories: true)
    try publish(Ownership(owner: app, generation: 1))

case "sessions":
    let rounds = Int(argument("rounds") ?? "1") ?? 1
    let hold = UInt32(argument("hold-us") ?? "100") ?? 100
    let staleDelay = UInt32(argument("stale-us") ?? "0") ?? 0
    print("ready")
    fflush(stdout)
    if let start = argument("start-at"), let target = UInt64(start) {
        while now() < target { usleep(50) }
    }
    for _ in 0..<rounds {
        if staleDelay > 0 {
            // A stale hint may say we own it; admission must still re-read under the lock.
            _ = readState()
            usleep(staleDelay)
        }
        session(hold: hold)
    }

case "hold":
    guard let descriptor = acquire(timeoutMs: 10_000), let state = readState(), state.owner == app else {
        exit(2)
    }
    emit("enter \(app) \(getpid()) \(state.generation)\n")
    print("held")
    fflush(stdout)
    if let release = argument("hold-ms"), let milliseconds = UInt32(release) {
        usleep(milliseconds * 1000)
        emit("exit \(app) \(getpid()) \(state.generation)\n")
        close(descriptor)
    } else {
        while true { sleep(60) }
    }

case "try-admit":
    let started = now()
    let descriptor = acquire(timeoutMs: Int(argument("timeout-ms") ?? "2000") ?? 2000)
    let elapsed = Double(now() - started) / 1_000_000
    let state = readState()
    let admitted = descriptor != nil && state?.owner == app
    if admitted, let generation = state?.generation {
        emit("enter \(app) \(getpid()) \(generation)\n")
        emit("exit \(app) \(getpid()) \(generation)\n")
    }
    if let descriptor { close(descriptor) }
    print(toJSON([
        "lock": descriptor != nil, "admitted": admitted, "lock_ms": elapsed,
        "owner": state?.owner ?? "", "generation": state?.generation ?? 0
    ]))

case "handoff":
    let target = argument("to") ?? ""
    let rounds = Int(argument("rounds") ?? "1") ?? 1
    var outcome = "changed"
    for _ in 0..<rounds {
        guard let descriptor = acquire(timeoutMs: Int(argument("timeout-ms") ?? "10000") ?? 10_000) else {
            outcome = "timeout"
            break
        }
        defer { close(descriptor) }
        guard var state = readState() else { exit(3) }
        let takesFromRelease = target.hasSuffix(".dev") && !state.owner.hasSuffix(".dev")
        if takesFromRelease && !flag("user-confirmed") {
            outcome = "refused"
            break
        }
        state.owner = target
        state.generation += 1
        try publish(state)
        emit("handoff \(target) \(getpid()) \(state.generation)\n")
    }
    print(toJSON(["outcome": outcome]))

case "pref-write":
    let domain = (argument("domain") ?? "") as CFString
    let stamp = now()
    CFPreferencesSetAppValue("value" as CFString, (argument("value") ?? "") as CFString, domain)
    CFPreferencesAppSynchronize(domain)
    print(stamp)

case "pref-watch":
    let domain = (argument("domain") ?? "") as CFString
    let expected = argument("value") ?? ""
    let deadline = now() + 10_000_000_000
    print("ready")
    fflush(stdout)
    while now() < deadline {
        CFPreferencesAppSynchronize(domain)
        if (CFPreferencesCopyAppValue("value" as CFString, domain) as? String) == expected {
            print(now())
            exit(0)
        }
        usleep(500)
    }
    print("timeout")

case "pref-read":
    let domain = (argument("domain") ?? "") as CFString
    CFPreferencesAppSynchronize(domain)
    print((CFPreferencesCopyAppValue("value" as CFString, domain) as? String) ?? "absent")

default:
    fatalError("unknown command")
}
