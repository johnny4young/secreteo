import Foundation

/// The provider could not produce a usable answer.
public enum PolishProviderError: Error, Equatable, Sendable, LocalizedError {
    case providerFailed(String)

    public var errorDescription: String? {
        switch self {
        case .providerFailed(let reason): "Polish provider failed: \(reason)"
        }
    }
}

enum OpenAICompatibleChatCodec {
    // swiftlint:disable:next function_parameter_count
    static func urlRequest(
        endpoint: URL, model: String, apiKey: String,
        system: String, user: String,
        temperature: Double, maxTokens: Int?
    ) throws -> URLRequest {
        var body: [String: Any] = [
            "model": model,
            "temperature": temperature,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user]
            ]
        ]
        if let maxTokens { body["max_tokens"] = maxTokens }

        var urlRequest = URLRequest(url: endpoint.appendingPathComponent("chat/completions"))
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    private struct ChatResponse: Decodable {
        let choices: [Choice]
    }
    private struct Choice: Decodable {
        let message: ChatCompletionMessage
    }

    static func parseContent(_ data: Data) throws -> String {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard
            let message = try? decoder.decode(ChatResponse.self, from: data)
                .choices.first?.message
        else {
            throw PolishProviderError.providerFailed("response is not a chat completion")
        }
        let answered = message.content.map { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if answered == true, let content = message.content { return content }
        // Thinking models can spend the whole token budget before answering.
        if message.hasReasoning {
            throw PolishProviderError.providerFailed("the model returned only its reasoning, no answer")
        }
        guard let content = message.content else {
            throw PolishProviderError.providerFailed("response is not a chat completion")
        }
        return content
    }

    static func responseContent(data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else {
            let body = String(data: data.prefix(300), encoding: .utf8) ?? ""
            throw PolishProviderError.providerFailed("HTTP \(statusCode): \(body)")
        }
        return try parseContent(data)
    }
}

private struct ChatCompletionMessage: Decodable {
    let content: String?
    let hasReasoning: Bool

    private enum CodingKeys: String, CodingKey { case content, reasoning, reasoningContent }

    // Providers shape the reasoning field differently; any non-empty value counts.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        content = try container.decodeIfPresent(String.self, forKey: .content)
        hasReasoning = [CodingKeys.reasoning, .reasoningContent].contains { key in
            (try? container.decodeNil(forKey: key)) == false
                && (try? container.decode(String.self, forKey: key))?.isEmpty != true
        }
    }
}
