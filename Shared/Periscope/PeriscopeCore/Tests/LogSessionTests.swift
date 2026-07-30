import Foundation
import PeriscopeCore
import Testing

struct LogSessionTests {
    @Test func currentDescribesThisLaunch() {
        let session = LogSession.current(attributes: [:])
        #expect(!session.appVersion.isEmpty)
        #expect(!session.buildNumber.isEmpty)
        #expect(!session.osVersion.isEmpty)
        #expect(!session.deviceModel.isEmpty)
    }

    @Test func eachCurrentSessionIsDistinct() {
        #expect(LogSession.current(attributes: [:]).id != LogSession.current(attributes: [:]).id)
    }

    @Test func currentCarriesTheAttributesItWasGiven() {
        let session = LogSession.current(attributes: [.optimizationLevel: "-Onone"])
        #expect(session.attributes == [.optimizationLevel: "-Onone"])
    }

    @Test func roundTripsThroughCodable() throws {
        let session = LogSession.fixture(attributes: [
            .commit: "a18a9309c5d6",
            .optimizationLevel: "-O",
        ])
        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(LogSession.self, from: data)
        #expect(decoded == session)
    }

    /// Attributes encode as a JSON object keyed by the attribute name, not the
    /// alternating key/value array a dictionary with non-string keys falls back
    /// to — so an exported session stays readable, and a stored payload doesn't
    /// change shape if the key type gains cases.
    @Test func attributesEncodeAsAnObjectKeyedByName() throws {
        let session = LogSession.fixture(attributes: [.configuration: "Release"])
        let data = try JSONEncoder().encode(session)
        let json = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any],
        )
        #expect(json["attributes"] as? [String: String] == ["configuration": "Release"])
    }
}
