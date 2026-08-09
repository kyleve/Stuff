import Foundation

public enum PatchlightHTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"
}

public struct PatchlightHTTPRequest: Sendable {
    public let method: PatchlightHTTPMethod
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(
        method: PatchlightHTTPMethod,
        url: URL,
        headers: [String: String] = [:],
        body: Data? = nil,
    ) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public struct PatchlightHTTPResponse: Sendable {
    public let statusCode: Int
    public let headers: [String: String]
    public let body: Data

    public init(statusCode: Int, headers: [String: String], body: Data) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }

    public func header(_ name: String) -> String? {
        headers[name.lowercased()]
    }
}

public protocol PatchlightHTTPTransport: Sendable {
    func send(_ request: PatchlightHTTPRequest) async throws -> PatchlightHTTPResponse
}

/// The sole live HTTP transport. It rejects every host outside Patchlight's
/// fixed GitHub and optional BYOK provider endpoints before creating a task.
public struct URLSessionPatchlightHTTPTransport: PatchlightHTTPTransport, @unchecked Sendable {
    private static let allowedHosts: Set<String> = [
        "api.github.com",
        "github.com",
        "api.openai.com",
        "api.anthropic.com",
    ]

    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: PatchlightHTTPRequest) async throws -> PatchlightHTTPResponse {
        guard request.url.scheme == "https",
              let host = request.url.host?.lowercased(),
              Self.allowedHosts.contains(host)
        else {
            throw PatchlightHTTPTransportError.disallowedEndpoint
        }

        var urlRequest = URLRequest(url: request.url)
        urlRequest.httpMethod = request.method.rawValue
        urlRequest.httpBody = request.body
        request.headers.forEach { urlRequest.setValue($0.value, forHTTPHeaderField: $0.key) }

        let (body, response) = try await session.data(for: urlRequest)
        guard let response = response as? HTTPURLResponse else {
            throw PatchlightHTTPTransportError.invalidResponse
        }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, pair in
            guard let name = pair.key as? String else { return }
            result[name.lowercased()] = String(describing: pair.value)
        }
        return PatchlightHTTPResponse(
            statusCode: response.statusCode,
            headers: headers,
            body: body,
        )
    }
}

public enum PatchlightHTTPTransportError: LocalizedError, Equatable, Sendable {
    case disallowedEndpoint
    case invalidResponse

    public var errorDescription: String? {
        switch self {
            case .disallowedEndpoint:
                "Patchlight refused a request outside its fixed service endpoints."
            case .invalidResponse:
                "The service returned a non-HTTP response."
        }
    }
}
