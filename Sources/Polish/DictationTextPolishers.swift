import DictationKit
import Foundation

/// Ollama's OpenAI-compatible endpoint, reached only through the egress
/// gateway, which refuses any destination that is not loopback.
public struct OpenAICompatibleDictationPolisher: DictationTextPolishing {
    public let endpoint: URL
    public let model: String
    private let apiKey: String
    private let gateway: any DataEgressGateway

    public init(endpoint: URL, model: String, apiKey: String, gateway: any DataEgressGateway) {
        self.endpoint = endpoint
        self.model = model
        self.apiKey = apiKey
        self.gateway = gateway
    }

    public func polish(_ text: String, recipe: String?) async throws -> String {
        let prompt = try DictationPolishPrompt.make(text, recipe: recipe)
        let request = try OpenAICompatibleChatCodec.urlRequest(
            endpoint: endpoint,
            model: model,
            apiKey: apiKey,
            system: prompt.system,
            user: prompt.user,
            temperature: 0.0,
            maxTokens: prompt.maximumResponseTokens)
        let metadata = DataEgressRequest(
            destination: DataEgressDestination(url: endpoint.appendingPathComponent("chat/completions")),
            providerDisclosure: DataEgressProviderDisclosure(
                providerID: endpoint.host ?? "Ollama",
                modelID: model))
        let response = try await gateway.perform(request, metadata: metadata)
        let content = try OpenAICompatibleChatCodec.responseContent(
            data: response.data,
            statusCode: response.statusCode)
        return DictationPolishPrompt.normalize(content, source: text)
    }
}

#if canImport(FoundationModels)
import FoundationModels

/// Apple's on-device model.
public struct FoundationModelDictationPolisher: DictationTextPolishing {
    private let unavailabilityReason: @Sendable () -> String?

    public init(
        unavailabilityReason: @escaping @Sendable () -> String? = {
            FoundationModelsAvailability.unavailabilityReason()
        }
    ) {
        self.unavailabilityReason = unavailabilityReason
    }

    public func polish(_ text: String, recipe: String?) async throws -> String {
        if let reason = unavailabilityReason() {
            throw DictationPolishUnavailable(reason: reason)
        }
        let prompt = try DictationPolishPrompt.make(text, recipe: recipe)
        let session = LanguageModelSession(instructions: prompt.system)
        let content = try await session.respond(
            to: prompt.user,
            options: .greedy(maximumResponseTokens: prompt.maximumResponseTokens)
        ).content
        return DictationPolishPrompt.normalize(content, source: text)
    }
}
#endif
