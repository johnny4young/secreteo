import Foundation
@testable import Polish
import Synchronization
import XCTest

final class OpenAICompatibleChatCodecTests: XCTestCase {
    func testRequestBodyIsOpenAICompatible() throws {
        let urlRequest = try OpenAICompatibleChatCodec.urlRequest(
            endpoint: URL(string: "http://localhost:11434/v1")!,
            model: "test-model", apiKey: "ollama",
            system: "be terse", user: "¿var vs let?",
            temperature: 0.3, maxTokens: 400)

        XCTAssertEqual(urlRequest.url?.absoluteString, "http://localhost:11434/v1/chat/completions")
        XCTAssertEqual(urlRequest.value(forHTTPHeaderField: "Authorization"), "Bearer ollama")

        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, "test-model")
        XCTAssertEqual(body["max_tokens"] as? Int, 400)
        let messages = try XCTUnwrap(body["messages"] as? [[String: String]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"], "system")
        XCTAssertEqual(messages[0]["content"], "be terse")
        XCTAssertEqual(messages[1]["role"], "user")
        XCTAssertEqual(messages[1]["content"], "¿var vs let?")
    }

    func testMaxTokensIsOmittedWhenNil() throws {
        let urlRequest = try OpenAICompatibleChatCodec.urlRequest(
            endpoint: URL(string: "http://localhost:11434/v1")!,
            model: "m", apiKey: "k",
            system: "s", user: "u", temperature: 0.3, maxTokens: nil)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(urlRequest.httpBody)) as? [String: Any])
        XCTAssertNil(body["max_tokens"])
    }

    func testParsesChatContentAndRejectsOtherShapes() throws {
        let payload = """
            {"choices": [{"message": {"content": "Hola."}}]}
            """
        XCTAssertEqual(
            try OpenAICompatibleChatCodec.parseContent(Data(payload.utf8)), "Hola.")
        XCTAssertThrowsError(
            try OpenAICompatibleChatCodec.parseContent(Data("{\"error\": \"nope\"}".utf8)))
    }

    func testReasoningOnlyChatResponseNamesTheCause() {
        for field in ["reasoning", "reasoning_content"] {
            let payload = #"{"choices": [{"message": {"content": null, "\#(field)": "draft"}}]}"#
            XCTAssertThrowsError(try OpenAICompatibleChatCodec.parseContent(Data(payload.utf8))) {
                XCTAssertTrue($0.localizedDescription.contains("only its reasoning"), field)
            }
        }
        let separate = #"{"choices": [{"message": {"content": "Hola.", "reasoning": "draft"}}]}"#
        XCTAssertEqual(try OpenAICompatibleChatCodec.parseContent(Data(separate.utf8)), "Hola.")
        let empty = #"{"choices": [{"message": {"content": null, "reasoning": ""}}]}"#
        XCTAssertThrowsError(try OpenAICompatibleChatCodec.parseContent(Data(empty.utf8))) {
            XCTAssertTrue($0.localizedDescription.contains("not a chat completion"))
        }
    }

    func testEmptyContentBesideReasoningIsReasoningOnly() {
        let payload = #"{"choices": [{"message": {"content": " \n", "reasoning": "draft"}}]}"#
        XCTAssertThrowsError(try OpenAICompatibleChatCodec.parseContent(Data(payload.utf8))) {
            XCTAssertTrue($0.localizedDescription.contains("only its reasoning"))
        }
        let noReasoning = #"{"choices": [{"message": {"content": ""}}]}"#
        XCTAssertEqual(try OpenAICompatibleChatCodec.parseContent(Data(noReasoning.utf8)), "")
    }

    func testStructuredReasoningFieldDoesNotHideTheContent() throws {
        let payload = #"{"choices": [{"message": {"content": "Hola.", "reasoning": {"summary": ["draft"]}}}]}"#
        XCTAssertEqual(try OpenAICompatibleChatCodec.parseContent(Data(payload.utf8)), "Hola.")
        let only = #"{"choices": [{"message": {"content": null, "reasoning_content": [{"text": "draft"}]}}]}"#
        XCTAssertThrowsError(try OpenAICompatibleChatCodec.parseContent(Data(only.utf8))) {
            XCTAssertTrue($0.localizedDescription.contains("only its reasoning"))
        }
    }

    func testAFailedStatusNamesItsCode() {
        XCTAssertThrowsError(try OpenAICompatibleChatCodec.responseContent(data: Data("down".utf8), statusCode: 503)) {
            XCTAssertEqual($0 as? PolishProviderError, .providerFailed("HTTP 503: down"))
        }
    }
}

final class OllamaServiceTests: XCTestCase {
    func testParsesTagsResponse() {
        let json = """
            {"models":[
              {"name":"gpt-oss:20b","size":13793000000,"details":{"parameter_size":"20.9B"}},
              {"name":"bare","size":1,"details":{}}
            ]}
            """
        let models = OllamaService.parseModels(Data(json.utf8))
        XCTAssertEqual(models.count, 2)
        XCTAssertEqual(models.first?.name, "gpt-oss:20b")
        XCTAssertEqual(models.first?.parameterSize, "20.9B")
        XCTAssertEqual(models.first?.bytes, 13_793_000_000)
        XCTAssertEqual(models.last?.parameterSize, "", "missing details degrade to empty")
    }

    func testEmptyOnGarbage() {
        XCTAssertTrue(OllamaService.parseModels(Data("not json".utf8)).isEmpty)
    }

    func testTheServiceIsOnLoopback() {
        XCTAssertEqual(DataEgressDestination(url: OllamaService.openAIEndpoint).scope, .localDevice)
    }

    func testModelsRefusesRedirectsOffLoopback() async {
        OllamaRedirectStubProtocol.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OllamaRedirectStubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let models = await OllamaService.models(session: session)
        XCTAssertNil(models)
        XCTAssertEqual(
            OllamaRedirectStubProtocol.requestedURLs.withLock { $0 },
            [OllamaService.baseURL.appendingPathComponent("api/tags")])
    }
}

private final class OllamaRedirectStubProtocol: URLProtocol {
    static let requestedURLs = Mutex<[URL]>([])

    static func reset() { requestedURLs.withLock { $0.removeAll() } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requestedURLs.withLock { $0.append(url) }
        if url.host == "localhost" {
            let redirect = HTTPURLResponse(
                url: url, statusCode: 302, httpVersion: "HTTP/1.1",
                headerFields: ["Location": "https://example.com/api/tags"])!
            client?.urlProtocol(
                self, wasRedirectedTo: URLRequest(url: URL(string: "https://example.com/api/tags")!),
                redirectResponse: redirect)
            client?.urlProtocol(self, didReceive: redirect, cacheStoragePolicy: .notAllowed)
            client?.urlProtocolDidFinishLoading(self)
        } else {
            let ok = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
            client?.urlProtocol(self, didReceive: ok, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(#"{"models":[{"name":"leaked"}]}"#.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class ReasoningEnvelopeTests: XCTestCase {
    func testThinkerTagIsNotReasoning() {
        XCTAssertEqual(ReasoningEnvelope.visibleText("<thinker>Visible</thinker>"), "<thinker>Visible</thinker>")
    }

    func testTagsQuotedInsideTheAnswerAreKept() throws {
        for answer in [
            "Wrap the draft in <think> tags before answering.",
            "The model printed <think>a</think> and then </think> literally.",
        ] {
            XCTAssertEqual(ReasoningEnvelope.visibleText(answer), answer)
        }
    }

    func testReasoningBeforeTheAnswerIsRemovedAndUnfinishedReasoningIsNil() {
        XCTAssertEqual(ReasoningEnvelope.visibleText("<think>plan</think>\nHola."), "Hola.")
        XCTAssertEqual(ReasoningEnvelope.visibleText("plan\n</think>\nHola."), "Hola.")
        XCTAssertNil(ReasoningEnvelope.visibleText("<think>plan"))
    }
}
