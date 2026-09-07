import Foundation

public struct HTTPResponse: Sendable {
    public let data: Data
    public let status: Int
    public let retryAfter: String?
    public init(data: Data, status: Int, retryAfter: String?) {
        self.data = data; self.status = status; self.retryAfter = retryAfter
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 90
        session = URLSession(
            configuration: configuration,
            delegate: SameOriginRedirects(),
            delegateQueue: nil,
        )
    }

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse
        else { throw URLError(.badServerResponse) }
        return HTTPResponse(
            data: data,
            status: response.statusCode,
            retryAfter: response.value(forHTTPHeaderField: "Retry-After"),
        )
    }
}

private final class SameOriginRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void,
    ) {
        let original = task.originalRequest?.url
        let sameOrigin = original?.host == request.url?.host && original?.port == request.url?
            .port && original?.scheme == request.url?.scheme
        completionHandler(sameOrigin ? request : nil)
    }
}
