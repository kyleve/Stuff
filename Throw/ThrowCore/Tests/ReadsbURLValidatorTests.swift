import Foundation
import Testing
@testable import ThrowCore

struct ReadsbURLValidatorTests {
    @Test(arguments: [
        "http://127.0.0.1/tar1090/data/aircraft.json",
        "http://192.168.1.20/data/aircraft.json",
        "http://receiver.local/data/aircraft.json",
        "https://public.example/data/aircraft.json",
    ])
    func acceptsSupportedReceiverURLs(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(try ReadsbURLValidator.validate(url) == url)
    }

    @Test(arguments: [
        "http://public.example/data/aircraft.json",
        "ftp://receiver.local/data/aircraft.json",
        "http://user:password@receiver.local/data/aircraft.json",
        "http://receiver.local/data/not-aircraft.json",
        "http://receiver.local/data/aircraft.json#fragment",
    ])
    func rejectsUnsupportedReceiverURLs(rawURL: String) throws {
        let url = try #require(URL(string: rawURL))
        #expect(throws: ThrowValidationError.invalidURL) {
            try ReadsbURLValidator.validate(url)
        }
    }

    @Test func derivesSiblingReceiverMetadataURL() throws {
        let aircraftURL = try #require(
            URL(string: "http://receiver.local/tar1090/data/aircraft.json?view=local"),
        )
        let receiverURL = try ReadsbURLValidator.receiverJSONURL(for: aircraftURL)
        #expect(
            receiverURL.absoluteString ==
                "http://receiver.local/tar1090/data/receiver.json?view=local",
        )
    }

    @Test func redirectValidationPreservesTheOriginalEndpointKind() throws {
        let receiverURL = try #require(
            URL(string: "http://receiver.local/data/receiver.json"),
        )
        let aircraftURL = try #require(
            URL(string: "http://receiver.local/data/aircraft.json"),
        )

        #expect(
            try ReadsbURLValidator.validateRedirectTarget(
                receiverURL,
                endpoint: .receiver,
            ) == receiverURL,
        )
        #expect(throws: ThrowValidationError.invalidURL) {
            try ReadsbURLValidator.validateRedirectTarget(
                aircraftURL,
                endpoint: .receiver,
            )
        }
    }

    @Test func receiverRedirectStillRejectsPublicHTTPHost() throws {
        let publicReceiverURL = try #require(
            URL(string: "http://public.example/data/receiver.json"),
        )
        #expect(throws: ThrowValidationError.invalidURL) {
            try ReadsbURLValidator.validateRedirectTarget(
                publicReceiverURL,
                endpoint: .receiver,
            )
        }
    }

    @Test(arguments: ["10.2.3.4", "172.16.0.1", "172.31.255.1", "169.254.2.1", "::1"])
    func recognizesLocalNetworkHosts(host: String) {
        #expect(ReadsbURLValidator.isLocalNetworkHost(host))
    }

    @Test(arguments: [
        "8.8.8.8",
        "172.32.0.1",
        "example.com",
        "fdexample.com",
        "fe8evil.com",
        "evil.10.0.0.1",
        "10.0.0.1.evil",
    ])
    func rejectsPublicHostsForHTTP(host: String) {
        #expect(ReadsbURLValidator.isLocalNetworkHost(host) == false)
    }
}
