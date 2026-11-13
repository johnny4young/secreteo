import Foundation

/// The opt-in timing log behind `-dictation-timing-log <absolute path>`: one JSON line per
/// session, appended to a file only this user can read. The shipped identity never opens it.
final class DictationTimingLog: Sendable {
    static let argument = "-dictation-timing-log"
    static let shippedIdentity = "com.johnny4young.secreteo"

    let url: URL
    private let queue = DispatchQueue(label: "dictation-timing-log")

    init?(arguments: [String], bundleIdentifier: String?) {
        guard bundleIdentifier != Self.shippedIdentity,
              let flag = arguments.firstIndex(of: Self.argument), arguments.indices.contains(flag + 1)
        else { return nil }
        let path = arguments[flag + 1]
        guard path.hasPrefix("/"), !path.hasSuffix("/") else { return nil }
        url = URL(fileURLWithPath: path)
    }

    func append(_ record: DictationSessionTimingRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let encoded = try? encoder.encode(record) else { return }
        let line = encoded + [0x0A]
        queue.async { [url] in Self.write(line, to: url) }
    }

    /// Waits for every append so far; tests read the file after it.
    func flush() { queue.sync {} }

    private static func write(_ line: Data, to url: URL) {
        let descriptor = open(url.path, O_WRONLY | O_APPEND | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        // A single write keeps concurrent appenders from interleaving inside a line.
        _ = line.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
    }
}
