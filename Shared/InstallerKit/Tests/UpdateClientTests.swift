import Foundation
@testable import InstallerKit
import Testing

struct UpdateClientTests {
    @Test func decodesValidFeedWithoutCredentials() async throws {
        let session = session()
        defer { session.invalidateAndCancel() }
        let catalog = try await UpdateClient(session: session).fetch(from: url("valid"))
        #expect(catalog == UpdateFixtures.catalog([2, 1], feedURL: url("valid")))
    }

    @Test(arguments: [401, 403, 404, 410, 418, 429, 500, 503])
    func preservesHTTPStatusBeforeTryingToDecodeTheFeed(_ status: Int) async {
        let session = session()
        defer { session.invalidateAndCancel() }
        await #expect(throws: UpdateClient.FetchError.httpStatus(status)) {
            try await UpdateClient(session: session).fetch(from: url("status-\(status)"))
        }
    }

    @Test(arguments: ["other-host", "insecure"])
    func distinguishesAnUnexpectedServerLocation(_ path: String) async {
        let session = session()
        defer { session.invalidateAndCancel() }
        await #expect(throws: UpdateClient.FetchError.unexpectedLocation) {
            try await UpdateClient(session: session).fetch(from: url(path))
        }
    }

    @Test func distinguishesNonHTTPAndOversizedResponses() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        let client = UpdateClient(session: session)
        await #expect(throws: UpdateClient.FetchError.invalidResponse) {
            try await client.fetch(from: url("non-http"))
        }
        await #expect(throws: UpdateClient.FetchError.responseTooLarge) {
            try await client.fetch(from: url("oversized"))
        }
    }

    @Test func preservesTransportAndFeedErrors() async {
        let session = session()
        defer { session.invalidateAndCancel() }
        let client = UpdateClient(session: session)
        await #expect {
            try await client.fetch(from: url("offline"))
        } throws: { error in
            (error as? URLError)?.code == .notConnectedToInternet
        }
        await #expect(throws: DecodingError.self) {
            try await client.fetch(from: url("malformed"))
        }
        await #expect(throws: UpdateCatalog.ValidationError.self) {
            try await client.fetch(from: url("bad-schema"))
        }
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    private func url(_ path: String) -> URL {
        URL(string: "https://updates.example.com/")!.appending(path: path)
            .appending(path: "updates.json")
    }
}
