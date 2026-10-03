import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct SampleAttributionRevisionTests {
    @Test func identityPreservesTheBareUUIDWireFormat() throws {
        let uuid = try #require(UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA"))
        let revisionID = SampleAttributionRevision.ID(rawValue: uuid)
        let encodedUUID = try JSONEncoder().encode(uuid)
        #expect(try JSONEncoder().encode(revisionID) == encodedUUID)
        #expect(try JSONDecoder().decode(SampleAttributionRevision.ID.self, from: encodedUUID)
            == revisionID)

        let revision = SampleAttributionRevision(
            id: revisionID,
            sampleID: .init(),
            updatedAt: Date(timeIntervalSince1970: 1000),
            replacementRegions: nil,
        )
        let encodedRevision = try JSONEncoder().encode(revision)
        let object = try #require(JSONSerialization.jsonObject(with: encodedRevision)
            as? [String: Any])
        #expect(object["id"] as? String == uuid.uuidString)
        #expect(object["sampleID"] as? String == revision.sampleID.rawValue.uuidString)
    }

    @Test func resetExclusionAndReplacementRemainDistinctOnTheWire() throws {
        let sampleID = LocationSample.ID()
        let replacements: [Set<Region>?] = [nil, [], [.newYork]]
        let revisions = replacements.map {
            SampleAttributionRevision(
                id: .init(rawValue: UUID()),
                sampleID: sampleID,
                updatedAt: Date(timeIntervalSince1970: 1000),
                replacementRegions: $0,
            )
        }
        let encoded = try JSONEncoder().encode(revisions)
        #expect(try JSONDecoder()
            .decode([SampleAttributionRevision].self, from: encoded) == revisions)
    }

    @Test func equalTimeRevisionsUseTheirStableIdentityToBreakTies() throws {
        let sampleID = LocationSample.ID()
        let lower = try SampleAttributionRevision(
            id: .init(rawValue: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))),
            sampleID: sampleID,
            updatedAt: Date(timeIntervalSince1970: 1000),
            replacementRegions: [],
        )
        let higher = try SampleAttributionRevision(
            id: .init(rawValue: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))),
            sampleID: sampleID,
            updatedAt: lower.updatedAt,
            replacementRegions: nil,
        )
        #expect(SampleAttributionRevision.newer(higher, than: lower))
        #expect(SampleAttributionRevision.newer(lower, than: higher) == false)
        let later = SampleAttributionRevision(
            id: lower.id,
            sampleID: sampleID,
            updatedAt: lower.updatedAt.addingTimeInterval(1),
            replacementRegions: [],
        )
        #expect(SampleAttributionRevision.newer(later, than: higher))
    }

    @Test func firstWriteUsesTheCurrentClock() {
        let now = Date(timeIntervalSince1970: 1000)
        #expect(SampleAttributionRevision.nextUpdatedAt(now: now, after: nil) == now)
    }

    @Test(arguments: [-1.0, 0, 1])
    func localWriteAdvancesPastObservedHistory(clockOffset: TimeInterval) throws {
        let prior = try SampleAttributionRevision(
            id: .init(rawValue: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))),
            sampleID: .init(),
            updatedAt: Date(timeIntervalSince1970: 1000),
            replacementRegions: [],
        )
        let now = prior.updatedAt.addingTimeInterval(clockOffset)
        let updatedAt = SampleAttributionRevision.nextUpdatedAt(now: now, after: prior)
        let next = try SampleAttributionRevision(
            id: .init(rawValue: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))),
            sampleID: prior.sampleID,
            updatedAt: updatedAt,
            replacementRegions: nil,
        )

        #expect(updatedAt > prior.updatedAt)
        #expect(updatedAt >= now)
        #expect(SampleAttributionRevision.newer(next, than: prior))
        if clockOffset > 0 {
            #expect(updatedAt == now)
        } else {
            #expect(updatedAt == prior.updatedAt.addingTimeInterval(0.001))
        }
    }
}
