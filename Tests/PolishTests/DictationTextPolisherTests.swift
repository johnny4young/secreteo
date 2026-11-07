import DictationKit
import Foundation
@testable import Polish
import XCTest

final class DictationTextPolisherTests: XCTestCase {
    func testOllamaPolishSendsOnlyTheDictationToLoopbackWithPolishMetadata() async throws {
        let gateway = CapturingDataEgressGateway(responseData: Self.chat("\"Mañana enviamos el informe.\""))
        let polisher = OllamaService.dictationPolisher(model: "qwen-local", gateway: gateway)

        let polished = try await polisher.polish("eh mañana enviamos el informe")

        XCTAssertEqual(polished, "Mañana enviamos el informe.")
        let snapshot = await gateway.snapshot()
        let captured = try XCTUnwrap(snapshot)
        XCTAssertEqual(captured.metadata.destination.scope, .localDevice)
        XCTAssertEqual(captured.metadata.providerDisclosure.modelID, "qwen-local")
        XCTAssertNoThrow(try URLSessionDataEgressGateway.validate(captured.request, metadata: captured.metadata))

        let body = try XCTUnwrap(captured.request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["temperature"] as? Double, 0)
        XCTAssertEqual(json["max_tokens"] as? Int, 64)
        let messages = try XCTUnwrap(json["messages"] as? [[String: String]])
        XCTAssertEqual(messages.first?["content"], DictationPolishPrompt.instructions)
        XCTAssertTrue(messages.last?["content"]?.contains("<dictation>\neh mañana enviamos el informe\n</dictation>") == true)
    }

    func testOllamaPolishRefusesOversizedTextBeforeTransport() async {
        let gateway = CapturingDataEgressGateway()
        let polisher = OllamaService.dictationPolisher(model: "qwen-local", gateway: gateway)

        do {
            _ = try await polisher.polish(String(repeating: "a", count: 2_001))
            XCTFail("text over the polish bound must not be sent")
        } catch {
            XCTAssertEqual(
                error as? DictationPolishPromptError,
                .textTooLong(actualCharacters: 2_001, maximumCharacters: 2_000))
        }
        let snapshot = await gateway.snapshot()
        XCTAssertNil(snapshot)
    }

    func testAppleUnavailableModelThrowsPolishUnavailableWithItsReason() async {
        let polisher = FoundationModelDictationPolisher(unavailabilityReason: { "Apple Intelligence is turned off" })

        do {
            _ = try await polisher.polish("hola qué tal")
            XCTFail("an unavailable on-device model must not run")
        } catch {
            XCTAssertEqual(
                error as? DictationPolishUnavailable,
                DictationPolishUnavailable(reason: "Apple Intelligence is turned off"))
        }
    }

    private static func chat(_ content: String) -> Data {
        let body: [String: Any] = ["choices": [["message": ["content": content]]]]
        return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
    }
}
