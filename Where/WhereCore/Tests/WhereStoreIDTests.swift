import Foundation
import Testing
@testable import WhereCore

/// Pins the exact `store://` identity strings ``WhereStoreID`` vends for log
/// `externalID`s, so the on-disk correlation key can't drift silently.
struct WhereStoreIDTests {
    @Test func dayIsCollectionAndISODay() {
        #expect(WhereStoreID.day("2026-06-05") == "store://days/2026-06-05")
    }

    @Test func yearIsCollectionAndYear() {
        #expect(WhereStoreID.year(2025) == "store://years/2025")
    }

    @Test func evidenceIsCollectionAndID() {
        let id = "5E1645CB-696E-4441-8154-5977E28251B8"
        #expect(WhereStoreID.evidence(id) == "store://evidence/\(id)")
    }

    @Test func sampleIsCollectionAndID() {
        let id = "B12614F7-46AD-41CF-B3DE-6BD3C0C4822B"
        #expect(WhereStoreID.sample(id) == "store://samples/\(id)")
    }

    /// The identities are well-formed `store://` URLs `StoreURL` can parse back,
    /// so the same scheme the store/backups use round-trips.
    @Test func identitiesParseAsStoreURLs() throws {
        let url = try #require(URL(string: WhereStoreID.day("2026-06-05")))
        let parts = try #require(StoreURL.parts(of: url))
        #expect(parts.collection == "days")
        #expect(parts.type == "2026-06-05")
        #expect(parts.items.isEmpty)
    }
}
