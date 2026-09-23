import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct SampleAttributionRevisionTests {
    @Test func resetExclusionAndReplacementRemainDistinctOnTheWire() throws {
        let sampleID = UUID()
        let replacements: [Set<Region>?] = [nil, [], [.newYork]]
        let revisions = replacements.map {
            SampleAttributionRevision(
                id: UUID(),
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
        let sampleID = UUID()
        let lower = try SampleAttributionRevision(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001")),
            sampleID: sampleID,
            updatedAt: Date(timeIntervalSince1970: 1000),
            replacementRegions: [],
        )
        let higher = try SampleAttributionRevision(
            id: #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002")),
            sampleID: sampleID,
            updatedAt: lower.updatedAt,
            replacementRegions: nil,
        )
        #expect(SampleAttributionRevision.newer(higher, than: lower))
        #expect(!SampleAttributionRevision.newer(lower, than: higher))
        let later = SampleAttributionRevision(
            id: lower.id,
            sampleID: sampleID,
            updatedAt: lower.updatedAt.addingTimeInterval(1),
            replacementRegions: [],
        )
        #expect(SampleAttributionRevision.newer(later, than: higher))
    }
}
