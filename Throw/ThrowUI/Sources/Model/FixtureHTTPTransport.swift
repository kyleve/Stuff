import Foundation
import ThrowCore

struct FixtureHTTPTransport: HTTPTransport {
    func response(for _: HTTPRequest) async throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: [:],
            data: Data(#"{"ac":[],"now":1787594400,"total":0}"#.utf8),
        )
    }
}
