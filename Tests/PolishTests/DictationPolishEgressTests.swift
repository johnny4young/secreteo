import Foundation
@testable import Polish
import XCTest

/// Dictated text leaves the process only for a model on this Mac, and leaves no journal behind.
final class DictationPolishEgressTests: XCTestCase {
    func testGatewayAcceptsDictationPolishOnlyOnLoopback() throws {
        let (request, metadata) = try polishRequest(endpoint: OllamaService.openAIEndpoint)
        XCTAssertNoThrow(try URLSessionDataEgressGateway.validate(request, metadata: metadata))

        for host in ["http://127.0.0.1:11434/v1", "http://[::1]:11434/v1"] {
            let (loopback, loopbackMetadata) = try polishRequest(endpoint: try XCTUnwrap(URL(string: host)))
            XCTAssertNoThrow(try URLSessionDataEgressGateway.validate(loopback, metadata: loopbackMetadata), host)
        }
        for host in ["http://192.168.1.20:11434/v1", "https://api.example.com/v1", "http://ollama.local:11434/v1",
                     "http://127.0.0.1.example.com/v1", "http://localhost.example.com/v1"] {
            let (remote, remoteMetadata) = try polishRequest(endpoint: try XCTUnwrap(URL(string: host)))
            XCTAssertThrowsError(try URLSessionDataEgressGateway.validate(remote, metadata: remoteMetadata)) { error in
                XCTAssertEqual(
                    error as? DataEgressGatewayError,
                    .invalidMetadata("Dictation polish requires a loopback destination"),
                    host)
            }
        }
    }

    func testGatewayRejectsForgedDictationPolishMetadata() throws {
        let (request, valid) = try polishRequest(endpoint: OllamaService.openAIEndpoint)
        let elsewhere = DataEgressDestination(url: try XCTUnwrap(URL(string: "http://127.0.0.1:11434/v1/other")))
        let forged: [(DataEgressRequest, String)] = [
            (DataEgressRequest(destination: elsewhere, providerDisclosure: valid.providerDisclosure),
             "destination does not match the network request"),
            (DataEgressRequest(
                destination: valid.destination,
                providerDisclosure: DataEgressProviderDisclosure(providerID: "api.example.com", modelID: "qwen-local")),
             "provider disclosure does not match the destination"),
            (DataEgressRequest(
                destination: valid.destination,
                providerDisclosure: DataEgressProviderDisclosure(providerID: "localhost", modelID: " ")),
             "Dictation polish egress requires a non-empty model POST"),
            (DataEgressRequest(
                destination: valid.destination,
                providerDisclosure: DataEgressProviderDisclosure(providerID: "localhost")),
             "Dictation polish egress requires a non-empty model POST"),
        ]
        for (metadata, message) in forged {
            XCTAssertThrowsError(try URLSessionDataEgressGateway.validate(request, metadata: metadata)) { error in
                XCTAssertEqual(error as? DataEgressGatewayError, .invalidMetadata(message))
            }
        }
    }

    func testGatewayRefusesAnythingButAPostWithABody() throws {
        let (request, metadata) = try polishRequest(endpoint: OllamaService.openAIEndpoint)
        var get = request
        get.httpMethod = "GET"
        var empty = request
        empty.httpBody = Data()
        for forged in [get, empty] {
            XCTAssertThrowsError(try URLSessionDataEgressGateway.validate(forged, metadata: metadata)) { error in
                XCTAssertEqual(
                    error as? DataEgressGatewayError,
                    .invalidMetadata("Dictation polish egress requires a non-empty model POST"))
            }
        }
    }

    func testARedirectIsNeverFollowed() async throws {
        let blocker = DataEgressRedirectBlocker()
        let url = try XCTUnwrap(URL(string: "http://localhost:11434/v1/chat/completions"))
        let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 307, httpVersion: nil, headerFields: nil))
        let task = URLSession.shared.dataTask(with: url)
        let elsewhere = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/v1")))
        let followed: URLRequest? = await withCheckedContinuation { continuation in
            blocker.urlSession(
                .shared, task: task, willPerformHTTPRedirection: response,
                newRequest: elsewhere
            ) { continuation.resume(returning: $0) }
        }
        XCTAssertNil(followed)
    }

    func testPolishImportsNoStoreUIOrJournal() throws {
        let sources = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/Polish")
        var found = Set<String>()
        for name in try FileManager.default.contentsOfDirectory(atPath: sources.path) where name.hasSuffix(".swift") {
            let text = try String(contentsOf: sources.appendingPathComponent(name), encoding: .utf8)
            found.formUnion(text.split(separator: "\n").compactMap { line in
                line.hasPrefix("import ") ? String(line.dropFirst("import ".count)) : nil
            })
        }
        XCTAssertTrue(found.isSubset(of: ["Foundation", "FoundationModels", "DictationKit"]), "\(found)")
    }

    private func polishRequest(endpoint: URL) throws -> (URLRequest, DataEgressRequest) {
        let request = try OpenAICompatibleChatCodec.urlRequest(
            endpoint: endpoint, model: "qwen-local", apiKey: "ollama",
            system: DictationPolishPrompt.instructions, user: "<dictation>\nhola\n</dictation>",
            temperature: 0, maxTokens: 64)
        let url = try XCTUnwrap(request.url)
        let metadata = DataEgressRequest(
            destination: DataEgressDestination(url: url),
            providerDisclosure: DataEgressProviderDisclosure(providerID: url.host ?? "", modelID: "qwen-local"))
        return (request, metadata)
    }
}
