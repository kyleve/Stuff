import Foundation
@testable import InstallerKit

/// Each request selects its response by path, so parallel tests share no mutable URL-loading state.
final class UpdateURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func stopLoading() {}

    override func startLoading() {
        guard let url = request.url else { preconditionFailure("A URL is required") }
        do {
            precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
            let scenario = url.deletingLastPathComponent().lastPathComponent
            if scenario == "offline" { throw URLError(.notConnectedToInternet) }
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let data: Data = switch scenario {
                case "oversized": Data(repeating: 32, count: 1_000_001)
                case "malformed": Data("not JSON".utf8)
                case "bad-schema": Data(#"{"schemaVersion":99,"apps":[]}"#.utf8)
                case let value where value.hasPrefix("status-"): Data("<html>Error</html>".utf8)
                default: try encoder.encode(UpdateFixtures.catalog([2, 1], feedURL: url))
            }
            let responseURL = switch scenario {
                case "other-host": URL(string: "https://other.example.com")!
                case "insecure": URL(string: "http://updates.example.com/updates.json")!
                default: url
            }
            let status = scenario.hasPrefix("status-") ? Int(scenario.dropFirst(7))! : 200
            let response: URLResponse = scenario == "non-http" ? URLResponse(
                url: url,
                mimeType: nil,
                expectedContentLength: data.count,
                textEncodingName: nil,
            ) : HTTPURLResponse(
                url: responseURL,
                statusCode: status,
                httpVersion: nil,
                headerFields: nil,
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
}
