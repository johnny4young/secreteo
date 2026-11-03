import DictationOwnership
import Foundation

// A second real process for the multiprocess tests. Logs `enter` and `exit` through one
// append-only file while it holds a lease, so file order is the order of events.
func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: "--\(name)"),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

func log(_ line: String) {
    guard let path = argument("log") else { return }
    let descriptor = open(path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { return }
    _ = "\(line) \(getpid())\n".withCString { write(descriptor, $0, strlen($0)) }
    close(descriptor)
}

let ownership = DictationOwnership(
    participant: argument("participant") ?? "",
    root: URL(fileURLWithPath: argument("root") ?? ""),
    isSandboxed: false,
    conditions: { ParticipantConditions(preferenceIsOn: true, missingForReadiness: nil, legacyPeerIsActive: false) })
let hold = useconds_t(argument("hold-us") ?? "100") ?? 100

switch CommandLine.arguments.dropFirst().first {
case "sessions":
    for _ in 0..<(Int(argument("rounds") ?? "1") ?? 1) {
        // The negative control: the same log with the lease skipped has to show overlaps.
        if CommandLine.arguments.contains("--skip-lease") {
            log("enter")
            usleep(hold)
            log("exit")
            continue
        }
        switch ownership.acquire(.global) {
        case .admitted(let lease):
            log("enter")
            usleep(hold)
            log("exit")
            lease.release()
        case .refused(let refusal):
            if case .busy = refusal { log("busy") } else { log("refused") }
        }
    }

case "hold":
    guard case .admitted(let lease) = ownership.acquire(.global) else { exit(2) }
    print("held")
    fflush(stdout)
    // Ends with its parent, so a crashed test run leaves nothing behind.
    withExtendedLifetime(lease) {
        while getppid() != 1 { sleep(1) }
    }

case "print-root":
    print(DictationOwnership.defaultRoot.path)

default:
    exit(64)
}
