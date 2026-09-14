import Foundation
import PortholeGitHub
import Testing

private final class GitHubTestURLProtocol: URLProtocol {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 403,
            httpVersion: nil,
            headerFields: ["Retry-After": "30"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("response".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

struct GitHubTransportTests {
    @Test func preservesStatusAndNormalizesHeadersWithoutLiveNetwork() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [GitHubTestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let transport = GitHubURLSessionTransport(session: session)
        let response = try await transport
            .send(URLRequest(url: #require(URL(string: "https://example.invalid/test"))))
        #expect(response.statusCode == 403)
        #expect(response.headers["retry-after"] == "30")
        #expect(response.body == Data("response".utf8))
    }
}
