import DictationKit
import Foundation
import Polish

/// The engine Polish and Rewrite use. Only engines on this Mac.
enum DictationPolishEngine: String, CaseIterable, Sendable {
    case appleOnDevice
    case ollama

    static let defaultsKey = "dictationPolishEngine"
    static let ollamaModelKey = "dictationPolishOllamaModel"

    static func current(in defaults: UserDefaults, capability: FoundationModelsCapability) -> Self {
        defaults.string(forKey: defaultsKey).flatMap(Self.init(rawValue:)) ?? capability.defaultPolishEngine
    }

    static func ollamaModel(in defaults: UserDefaults) -> String? {
        let model = (defaults.string(forKey: ollamaModelKey) ?? "").trimmingCharacters(in: .whitespaces)
        return model.isEmpty ? nil : model
    }
}

/// The engine choice sampled for one polish call.
struct DictationPolishSelection: Sendable {
    let engine: DictationPolishEngine
    let ollamaModel: String?
    let ollamaEndpoint: URL
    let foundationModelsCapability: FoundationModelsCapability

    @MainActor
    static func current(in defaults: UserDefaults) -> Self {
        let capability = FoundationModelsCapability.current()
        return Self(
            engine: DictationPolishEngine.current(in: defaults, capability: capability),
            ollamaModel: DictationPolishEngine.ollamaModel(in: defaults),
            ollamaEndpoint: OllamaService.openAIEndpoint,
            foundationModelsCapability: capability)
    }
}

/// Reads the selected engine on every call and polishes only with it:
/// an engine that cannot run throws `DictationPolishUnavailable`, never falls through.
struct DictationPolishRouter: DictationTextPolishing {
    let selection: @MainActor @Sendable () -> DictationPolishSelection?
    let makeApple: @MainActor @Sendable () -> any DictationTextPolishing
    let makeOllama: @Sendable (_ endpoint: URL, _ model: String) -> any DictationTextPolishing

    func polish(_ text: String, recipe: String?) async throws -> String {
        guard let current = await selection() else {
            throw DictationPolishUnavailable(reason: L10n.text("Polish is unavailable right now."))
        }
        let polisher = try await resolve(current)
        do {
            return try await polisher.polish(text, recipe: recipe)
        } catch {
            throw Self.presented(error)
        }
    }

    private func resolve(_ current: DictationPolishSelection) async throws -> any DictationTextPolishing {
        switch current.engine {
        case .ollama:
            guard let model = current.ollamaModel else {
                throw DictationPolishUnavailable(reason: L10n.text(
                    "Choose an Ollama model in Settings to polish dictations."))
            }
            guard DataEgressDestination(url: current.ollamaEndpoint).scope == .localDevice else {
                throw DictationPolishUnavailable(reason: L10n.text("Polish only uses Ollama on this Mac."))
            }
            return makeOllama(current.ollamaEndpoint, model)
        case .appleOnDevice:
            switch current.foundationModelsCapability {
            case .unavailable(let reason):
                throw DictationPolishUnavailable(reason: L10n.format(
                    "Apple Intelligence is unavailable: %@.", reason))
            case .available:
                return await makeApple()
            }
        }
    }

    /// An unreachable engine becomes a short reason; cancellation and generation
    /// failures pass through unchanged.
    static func presented(_ error: any Error) -> any Error {
        if error is DictationPolishUnavailable || error is CancellationError { return error }
        if let url = error as? URLError, unreachableCodes.contains(url.code) {
            return DictationPolishUnavailable(reason: L10n.text(
                "Ollama is not responding on localhost:11434. Install it and run “ollama serve”."))
        }
        return error
    }

    private static let unreachableCodes: Set<URLError.Code> = [
        .cannotConnectToHost, .cannotFindHost, .networkConnectionLost, .notConnectedToInternet
    ]
}

extension DictationPolishRouter {
    /// Polishes with the engine selected in Settings at call time.
    @MainActor
    static func live(defaults: UserDefaults) -> Self {
        DictationPolishRouter(
            selection: { DictationPolishSelection.current(in: defaults) },
            makeApple: { FoundationModelDictationPolisher() },
            makeOllama: { endpoint, model in
                OpenAICompatibleDictationPolisher(
                    endpoint: endpoint, model: model, apiKey: "ollama", gateway: URLSessionDataEgressGateway())
            })
    }
}
