import Foundation

/// Whether an outbound destination is provably loopback or may leave the Mac.
/// Unknown and private-network hosts are conservatively remote.
public enum DataEgressDestinationScope: String, Codable, Sendable {
    case localDevice = "local-device"
    case remote
}

public struct DataEgressDestination: Equatable, Sendable {
    public let url: URL
    public let scope: DataEgressDestinationScope

    public init(url: URL) {
        self.url = url
        scope = url.host.map(Self.scope(forHost:)) ?? .remote
    }

    /// Shared conservative host classifier for request validation.
    /// Unknown and private-network hosts remain remote.
    public static func scope(forHost rawHost: String) -> DataEgressDestinationScope {
        var host = rawHost.lowercased()
        if host.hasPrefix("[") && host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") { host.removeLast() }
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1" {
            return .localDevice
        }
        let octets = host.split(separator: ".", omittingEmptySubsequences: false)
        guard octets.count == 4,
              octets.allSatisfy({ octet in
                  guard let value = Int(octet) else { return false }
                  return value >= 0 && value <= 255
              }),
              octets.first == "127"
        else { return .remote }
        return .localDevice
    }
}

public struct DataEgressProviderDisclosure: Equatable, Sendable {
    public let providerID: String
    public let modelID: String?

    public init(providerID: String, modelID: String? = nil) {
        self.providerID = providerID
        self.modelID = modelID
    }
}

/// Content-free policy metadata for one Polish request. The dictated text travels only
/// in the request body.
public struct DataEgressRequest: Equatable, Sendable {
    public let destination: DataEgressDestination
    public let providerDisclosure: DataEgressProviderDisclosure

    public init(destination: DataEgressDestination, providerDisclosure: DataEgressProviderDisclosure) {
        self.destination = destination
        self.providerDisclosure = providerDisclosure
    }
}

public struct DataEgressResponse: Sendable {
    public let data: Data
    public let statusCode: Int

    public init(data: Data, statusCode: Int) {
        self.data = data
        self.statusCode = statusCode
    }
}

public enum DataEgressGatewayError: Error, Equatable, Sendable {
    case invalidMetadata(String)
    case nonHTTPResponse
    case responseTooLarge(actualBytes: Int, maximumBytes: Int)
}

/// The only transport for dictated text leaving the process.
public protocol DataEgressGateway: Sendable {
    func perform(
        _ networkRequest: URLRequest,
        metadata: DataEgressRequest
    ) async throws -> DataEgressResponse
}
