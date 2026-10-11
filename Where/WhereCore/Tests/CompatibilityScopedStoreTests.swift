import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct CompatibilityScopedStoreTests {
    @Test func homeRegionHistoryForwardsUntilTheScopeIsRevoked() async throws {
        let base = try SwiftDataStore.inMemory()
        let permit = DataAccessPermit()
        let scoped = CompatibilityScopedStore(base: base, permit: permit)
        let home = try HomeRegionRecord(id: UUID(), region: .california, updatedAt: Date())
        let historical = try HomeRegionRecord(id: UUID(), region: nil, updatedAt: Date())

        try await scoped.perform {
            try await scoped.restoreHomeRegionRecord(home)
            try await scoped.restoreHomeRegionRecord(historical)
        }
        #expect(Set(try await scoped.homeRegionRecords()) == [home, historical])
        try await scoped.perform {
            try await scoped.replaceHomeRegionRecord(with: home)
        }
        #expect(try await base.homeRegionRecords() == [home])

        permit.revoke()
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            _ = try await scoped.homeRegionRecords()
        }
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await scoped.restoreHomeRegionRecord(historical)
        }
        await #expect(throws: DataCompatibilityError.accessRevoked) {
            try await scoped.replaceHomeRegionRecord(with: historical)
        }
        #expect(try await base.homeRegionRecords() == [home])
    }
}
