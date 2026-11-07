import DictationKit
import Foundation
import Polish
@testable import DictationSession
import XCTest

final class DictationPolishRouterTests: XCTestCase {
    func testSelectedEngineIsReadOnEveryCall() async throws {
        let selected = EngineSelectionBox(.ollama)
        let router = makeRouter(selected: selected)

        let first = try await router.polish("hola")
        selected.engine = .appleOnDevice
        let second = try await router.polish("hola")

        XCTAssertEqual([first, second], ["ollama", "apple"])
    }

    func testTheRecipeReachesTheSelectedEngine() async throws {
        let router = makeRouter(selected: EngineSelectionBox(.ollama))

        let polished = try await router.polish("hola", recipe: "Make it formal.")

        XCTAssertEqual(polished, "ollama|Make it formal.")
    }

    func testUnconfiguredOllamaNeverFallsThroughToAnotherEngine() async {
        let router = makeRouter(selected: EngineSelectionBox(.ollama), ollamaModel: nil)

        await assertUnavailable(router, "Choose an Ollama model in Settings to polish dictations.")
    }

    func testNonLoopbackOllamaEndpointIsRefusedBeforeAnyRequest() async {
        let built = BuildCounter()
        let router = makeRouter(
            selected: EngineSelectionBox(.ollama),
            ollamaEndpoint: URL(string: "http://192.168.1.20:11434/v1")!,
            built: built)

        await assertUnavailable(router, "Polish only uses Ollama on this Mac.")
        XCTAssertEqual(built.count, 0)
    }

    func testUnreachableOllamaBecomesUnavailable() async {
        let router = makeRouter(
            selected: EngineSelectionBox(.ollama),
            ollama: ThrowingPolisher(error: URLError(.cannotConnectToHost)))

        await assertUnavailable(
            router, "Ollama is not responding on localhost:11434. Install it and run “ollama serve”.")
    }

    func testAppleCapabilityGapsStayExplicit() async {
        await assertUnavailable(
            makeRouter(selected: EngineSelectionBox(.appleOnDevice), capability: .unavailable("it is off")),
            "Apple Intelligence is unavailable: it is off.")
    }

    func testCancellationAndGenerationFailuresPassThrough() async {
        let cancelled = makeRouter(
            selected: EngineSelectionBox(.ollama), ollama: ThrowingPolisher(error: CancellationError()))
        do {
            _ = try await cancelled.polish("hola")
            XCTFail("cancellation must surface")
        } catch {
            XCTAssertTrue(error is CancellationError)
        }

        let failed = makeRouter(
            selected: EngineSelectionBox(.ollama),
            ollama: ThrowingPolisher(error: PolishProviderError.providerFailed("HTTP 500")))
        do {
            _ = try await failed.polish("hola")
            XCTFail("a generation failure must surface")
        } catch {
            XCTAssertFalse(error is DictationPolishUnavailable)
        }
    }

    func testMissingServicesAreUnavailable() async {
        let router = DictationPolishRouter(
            selection: { nil },
            makeApple: { FixedPolisher(text: "apple") },
            makeOllama: { _, _ in FixedPolisher(text: "ollama") })

        await assertUnavailable(router, "Polish is unavailable right now.")
    }

    @MainActor
    func testTheDefaultEngineIsOneThatCanRunHere() {
        let defaults = UserDefaults(suiteName: "polish-engine-\(UUID())")!
        XCTAssertEqual(DictationPolishEngine.current(in: defaults, capability: .available), .appleOnDevice)
        XCTAssertEqual(DictationPolishEngine.current(in: defaults, capability: .unavailable("off")), .ollama)
        defaults.set("mlx", forKey: DictationPolishEngine.defaultsKey)
        XCTAssertEqual(DictationPolishEngine.current(in: defaults, capability: .available), .appleOnDevice)
        defaults.set("ollama", forKey: DictationPolishEngine.defaultsKey)
        defaults.set("  ", forKey: DictationPolishEngine.ollamaModelKey)
        XCTAssertEqual(DictationPolishEngine.current(in: defaults, capability: .available), .ollama)
        XCTAssertNil(DictationPolishEngine.ollamaModel(in: defaults))
    }

    private func makeRouter(
        selected: EngineSelectionBox,
        ollamaModel: String? = "qwen-local",
        ollamaEndpoint: URL = OllamaService.openAIEndpoint,
        capability: FoundationModelsCapability = .available,
        ollama: any DictationTextPolishing = FixedPolisher(text: "ollama"),
        built: BuildCounter = BuildCounter()
    ) -> DictationPolishRouter {
        DictationPolishRouter(
            selection: {
                DictationPolishSelection(
                    engine: selected.engine,
                    ollamaModel: ollamaModel,
                    ollamaEndpoint: ollamaEndpoint,
                    foundationModelsCapability: capability)
            },
            makeApple: { FixedPolisher(text: "apple") },
            makeOllama: { endpoint, model in
                built.increment()
                XCTAssertEqual(endpoint, ollamaEndpoint)
                XCTAssertEqual(model, ollamaModel)
                return ollama
            })
    }

    private func assertUnavailable(
        _ router: DictationPolishRouter,
        _ reason: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await router.polish("hola qué tal")
            XCTFail("expected unavailable", file: file, line: line)
        } catch {
            XCTAssertEqual(
                error as? DictationPolishUnavailable,
                DictationPolishUnavailable(reason: reason),
                file: file,
                line: line)
        }
    }
}

private final class EngineSelectionBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: DictationPolishEngine

    init(_ engine: DictationPolishEngine) { value = engine }

    var engine: DictationPolishEngine {
        get { lock.withLock { value } }
        set { lock.withLock { value = newValue } }
    }
}

private final class BuildCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    var count: Int { lock.withLock { value } }
    func increment() { lock.withLock { value += 1 } }
}

private struct FixedPolisher: DictationTextPolishing {
    let text: String
    func polish(_: String, recipe: String?) async throws -> String { recipe.map { text + "|" + $0 } ?? text }
}

private struct ThrowingPolisher: DictationTextPolishing {
    let error: any Error
    func polish(_: String, recipe: String?) async throws -> String { throw error }
}
