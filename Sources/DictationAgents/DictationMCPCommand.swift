import DictationStore
import Foundation

/// `secreteo-mcp [--db <path>]`: a local MCP server over stdio. Register it with e.g.
///
///     claude mcp add secreteo -- /Applications/Secreteo.app/Contents/Helpers/secreteo-mcp
public enum DictationMCPCommand {
    public static func run(arguments: [String], executable: URL) async {
        let server = MCPServer(
            serverName: "secreteo", serverVersion: version(executable: executable),
            instructions: DictationToolbox.serverInstructions,
            tools: DictationToolbox.tools(reader: .opening(databaseURL(arguments: arguments, executable: executable))))
        while let line = readLine(strippingNewline: true) {
            if let response = await server.handleLine(line) {
                print(response)
                fflush(stdout)
            }
        }
    }

    static func databaseURL(arguments: [String], executable: URL) -> URL {
        if let flag = arguments.firstIndex(of: "--db"), arguments.indices.contains(flag + 1) {
            return URL(fileURLWithPath: arguments[flag + 1])
        }
        let identifier = appBundle(containing: executable)?.bundleIdentifier ?? "com.johnny4young.secreteo"
        return DictationStore.defaultURL(bundleIdentifier: identifier)
    }

    /// The helper lives inside the app, so the Dev identity reads its own database.
    static func appBundle(containing executable: URL) -> Bundle? {
        var url = executable.resolvingSymlinksInPath().deletingLastPathComponent()
        while url.path != "/" {
            if url.pathExtension == "app" { return Bundle(url: url) }
            url.deleteLastPathComponent()
        }
        return nil
    }

    private static func version(executable: URL) -> String {
        appBundle(containing: executable)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? "0.0.0"
    }
}

extension DictationAgentReader {
    /// Opens the app's database on the first call that finds it, so a client set up
    /// before Secreteo first ran starts working without a restart.
    static func opening(_ url: URL) -> Self {
        let opener = StoreOpener(url: url)
        return Self(
            page: { filter, offset, limit in
                try await ReadDictationsForAgents(store: try await opener.store()).execute(
                    .init(filter: filter, offset: offset, limit: limit))
            },
            record: { try await ReadDictationForAgents(store: try await opener.store()).execute($0) })
    }
}

private actor StoreOpener {
    let url: URL
    private var opened: DictationStore?

    init(url: URL) {
        self.url = url
    }

    func store() throws -> DictationStore {
        if let opened { return opened }
        do {
            let store = try DictationStore.openForReading(at: url)
            opened = store
            return store
        } catch DictationStoreError.notCreated {
            throw DictationMCPError.notCreated
        } catch DictationStoreError.needsUpgrade, DictationStoreError.newerSchema {
            throw DictationMCPError.versionMismatch
        }
    }
}

enum DictationMCPError: Error, Equatable, LocalizedError {
    case notCreated
    case versionMismatch

    var errorDescription: String? {
        switch self {
        case .notCreated: "Secreteo has not created its dictation history yet. Open Secreteo once."
        case .versionMismatch: "This helper and the Secreteo that saved the history are different versions."
        }
    }
}
