import Foundation
import ThrowCore

struct FixtureHTTPTransport: HTTPTransport {
    func response(for request: HTTPRequest) async throws -> HTTPResponse {
        let data = if request.url.path() == "/api/usage" {
            Data(
                #"{"data":[{"endpoint":"live/flight-positions/full?{filters}","request_count":12,"credits":2400}]}"#
                    .utf8,
            )
        } else if request.url.host() == "fr24api.flightradar24.com" {
            Data(#"{"data":[]}"#.utf8)
        } else {
            Data(#"{"ac":[],"now":1787594400,"total":0}"#.utf8)
        }
        return HTTPResponse(
            statusCode: 200,
            headers: [:],
            data: data,
        )
    }
}
