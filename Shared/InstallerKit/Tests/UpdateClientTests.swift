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

    @Test(arguments: ["missing", "other-host", "oversized", "malformed", "bad-schema"])
    func rejectsUnusableResponses(_ path: String) async {
        let session = session()
        defer { session.invalidateAndCancel() }
        await #expect(throws: (any Error).self) {
            try await UpdateClient(session: session).fetch(from: url(path))
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
