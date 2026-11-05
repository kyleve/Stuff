import RegionKit
import Testing
@testable import WhereCore

struct RecordingGeographyTests {
    @Test func specificCorrectionsPreserveMultipleRegions() throws {
        let geography = try RecordingGeography(
            knownRegions: [.california, .newYork],
            includesUnknownPresence: false,
        )
        #expect(geography.presence == [.california, .newYork])
        #expect(geography.establishesAgreement)
        #expect(geography.singleRegion == nil)
    }

    @Test func unknownAndExcludedPresenceDoNotEstablishAgreement() throws {
        let unknown = try RecordingGeography(knownRegions: [], includesUnknownPresence: true)
        let excluded = try RecordingGeography(knownRegions: [], includesUnknownPresence: false)
        let mixed = try RecordingGeography(
            knownRegions: [.california],
            includesUnknownPresence: true,
        )
        #expect(unknown.presence == [.other])
        #expect(excluded.presence.isEmpty)
        #expect(mixed.presence == [.california, .other])
        #expect(!unknown.establishesAgreement && !excluded.establishesAgreement && !mixed
            .establishesAgreement)
        #expect(throws: RecordingGeography.ValidationError.self) {
            try RecordingGeography(knownRegions: [.other], includesUnknownPresence: false)
        }
    }
}
