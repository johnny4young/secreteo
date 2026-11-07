import Foundation

/// Local models through Ollama's OpenAI-compatible endpoint on this Mac. It needs no key,
/// and Polish talks to it only through the loopback gateway.
public enum OllamaService {
    public static let baseURL = URL(string: "http://localhost:11434")!
    public static var openAIEndpoint: URL { baseURL.appendingPathComponent("v1") }

    public struct Model: Sendable, Identifiable, Equatable {
        public let name: String
        public let parameterSize: String
        public let bytes: Int64
        public var id: String { name }

        public init(name: String, parameterSize: String, bytes: Int64) {
            self.name = name
            self.parameterSize = parameterSize
            self.bytes = bytes
        }
    }

    /// The models the user has pulled, or nil when Ollama does not answer.
    public static func models(session: URLSession = .shared) async -> [Model]? {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/tags"))
        request.timeoutInterval = 3
        guard let (data, response) = try? await session.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return parseModels(data)
    }

    private struct Tags: Decodable {
        let models: [Entry]
    }
    private struct Entry: Decodable {
        let name: String
        let size: Int64?
        let details: Details?
    }
    private struct Details: Decodable {
        let parameterSize: String?
    }

    static func parseModels(_ data: Data) -> [Model] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let tags = try? decoder.decode(Tags.self, from: data) else { return [] }
        return tags.models.map {
            Model(
                name: $0.name,
                parameterSize: $0.details?.parameterSize ?? "",
                bytes: $0.size ?? 0)
        }
    }

    /// Pinned to the fixed loopback service.
    public static func dictationPolisher(
        model: String,
        gateway: any DataEgressGateway
    ) -> OpenAICompatibleDictationPolisher {
        OpenAICompatibleDictationPolisher(
            endpoint: openAIEndpoint,
            model: model,
            apiKey: "ollama",
            gateway: gateway)
    }
}
