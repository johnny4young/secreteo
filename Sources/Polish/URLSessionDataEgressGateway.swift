import Foundation

/// Sends one Polish request to a model on this Mac. Metadata is validated before
/// URLSession can observe the payload, and nothing is journaled.
public struct URLSessionDataEgressGateway: DataEgressGateway {
    static let maximumResponseBytes = 2 * 1_024 * 1_024
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func perform(
        _ networkRequest: URLRequest,
        metadata: DataEgressRequest
    ) async throws -> DataEgressResponse {
        try Self.validate(networkRequest, metadata: metadata)
        let (bytes, response) = try await session.bytes(
            for: networkRequest,
            delegate: DataEgressRedirectBlocker())
        guard let http = response as? HTTPURLResponse else {
            throw DataEgressGatewayError.nonHTTPResponse
        }
        let maximumBytes = Self.maximumResponseBytes
        if http.expectedContentLength > Int64(maximumBytes) {
            throw DataEgressGatewayError.responseTooLarge(
                actualBytes: Int(clamping: http.expectedContentLength),
                maximumBytes: maximumBytes)
        }
        var data = Data()
        if http.expectedContentLength > 0 {
            data.reserveCapacity(min(
                Int(clamping: http.expectedContentLength),
                maximumBytes))
        }
        for try await byte in bytes {
            guard data.count < maximumBytes else {
                throw DataEgressGatewayError.responseTooLarge(
                    actualBytes: maximumBytes + 1,
                    maximumBytes: maximumBytes)
            }
            data.append(byte)
        }
        return DataEgressResponse(data: data, statusCode: http.statusCode)
    }

    static func validate(
        _ networkRequest: URLRequest,
        metadata: DataEgressRequest
    ) throws {
        let url = try validateDestination(networkRequest, metadata: metadata)
        try validateProvider(metadata.providerDisclosure, for: url)
        try validateDictationPolishRequest(networkRequest, metadata: metadata)
    }

    private static func validateDestination(
        _ networkRequest: URLRequest,
        metadata: DataEgressRequest
    ) throws -> URL {
        guard let url = networkRequest.url,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else {
            throw DataEgressGatewayError.invalidMetadata(
                "destination is not an HTTP endpoint")
        }
        guard metadata.destination == DataEgressDestination(url: url)
        else {
            throw DataEgressGatewayError.invalidMetadata(
                "destination does not match the network request")
        }
        return url
    }

    private static func validateProvider(
        _ disclosure: DataEgressProviderDisclosure,
        for url: URL
    ) throws {
        let providerID = disclosure.providerID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !providerID.isEmpty,
              providerID.caseInsensitiveCompare(url.host ?? "") == .orderedSame
        else {
            throw DataEgressGatewayError.invalidMetadata(
                "provider disclosure does not match the destination")
        }
    }

    private static func validateDictationPolishRequest(
        _ networkRequest: URLRequest,
        metadata: DataEgressRequest
    ) throws {
        let modelID = metadata.providerDisclosure.modelID?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard networkRequest.httpMethod == "POST",
              networkRequest.httpBody?.isEmpty == false,
              modelID?.isEmpty == false
        else {
            throw DataEgressGatewayError.invalidMetadata(
                "Dictation polish egress requires a non-empty model POST")
        }
        guard metadata.destination.scope == .localDevice else {
            throw DataEgressGatewayError.invalidMetadata(
                "Dictation polish requires a loopback destination")
        }
    }
}

/// A validated endpoint cannot silently redirect dictated text to another
/// destination. A redirect is returned to the caller as the original 3xx response.
/// It stores nothing, so it is safe to share across threads.
final class DataEgressRedirectBlocker: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
