import Foundation
import RegionKit
import Testing
@testable import WhereCore

struct PlannedStayCoordinatorTests {
    private static let now = Date(timeIntervalSince1970: 1_780_000_000)

    private static func coordinator(store: SwiftDataStore) -> PlannedStayCoordinator {
        PlannedStayCoordinator(store: store, now: { now })
    }

    @Test func independentStaysSurviveEditingAndDeletingAnotherStay() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let october = try PlannedStayTestSupport.stay()
        let december = try PlannedStayTestSupport.stay(
            arrival: .init(year: 2026, month: 12, day: 10),
            departure: .init(year: 2026, month: 12, day: 20),
        )
        try await coordinator.create(october)
        try await coordinator.create(december)
        let edited = try PlannedStayTestSupport.stay(id: october.id, region: .california)
        try await coordinator.update(edited)

        #expect(try await coordinator.snapshot().stays == [edited, december])
        try await coordinator.delete(stayID: october.id)
        #expect(try await coordinator.snapshot().stays == [december])
        let records = try await store.plannedStayRecords()
        #expect(records.count == 2)
        #expect(records.first { $0.stayID == october.id }?.value == nil)
    }

    @Test func readingRetainsCompletedPlansAndDoesNotExpireRecords() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let completed = try PlannedStayTestSupport.stay(
            arrival: .init(year: 2025, month: 1, day: 1),
            departure: .init(year: 2025, month: 1, day: 10),
        )
        try await coordinator.create(completed)
        let before = try await store.plannedStayRecords()

        #expect(try await coordinator.snapshot().stays == [completed])
        #expect(try await store.plannedStayRecords() == before)
    }

    @Test func newestSyncedRevisionWinsSeparatelyForEachStay() async throws {
        let store = try SwiftDataStore.inMemory()
        let older = try PlannedStayTestSupport.stay(region: .california)
        let newer = try PlannedStayTestSupport.stay(id: older.id, region: .newYork)
        let unrelated = try PlannedStayTestSupport.stay(region: .canada)
        let oldRecord = try PlannedStayTestSupport.record(stay: older, updatedAt: Self.now)
        let newRecord = try PlannedStayTestSupport.record(
            stay: newer,
            updatedAt: Self.now.addingTimeInterval(1),
        )
        let unrelatedRecord = try PlannedStayTestSupport.record(
            stay: unrelated,
            updatedAt: Self.now,
        )
        try await store.perform {
            try await store.restorePlannedStayRecord(newRecord)
            try await store.restorePlannedStayRecord(oldRecord)
            try await store.restorePlannedStayRecord(unrelatedRecord)
        }

        let snapshot = try await Self.coordinator(store: store).snapshot()
        #expect(Set(snapshot.stays) == Set([newer, unrelated]))
    }

    @Test func deletionAdvancesPastAFutureRevisionAndDefeatsItsDelayedReimport() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let stay = try PlannedStayTestSupport.stay()
        let future = try PlannedStayTestSupport.record(
            stay: stay,
            updatedAt: Self.now.addingTimeInterval(60),
        )
        try await store.perform { try await store.restorePlannedStayRecord(future) }
        try await coordinator.delete(stayID: stay.id)
        let tombstone = try #require(await store.plannedStayRecords().first)
        #expect(tombstone.updatedAt > future.updatedAt)
        #expect(tombstone.value == nil)

        try await store.perform { try await store.restorePlannedStayRecord(future) }
        #expect(try await coordinator.snapshot().stays.isEmpty)
    }

    @Test func staleEditorCannotRecreateADeletedStay() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let stay = try PlannedStayTestSupport.stay()
        try await coordinator.create(stay)
        try await coordinator.delete(stayID: stay.id)

        await #expect(throws: PlannedStayCoordinator.PlanningError.stayNotFound) {
            try await coordinator.update(stay)
        }
        #expect(try await coordinator.snapshot().stays.isEmpty)
    }

    @Test func retryingAnIdenticalCreateKeepsTheRevision() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let stay = try PlannedStayTestSupport.stay()
        try await coordinator.create(stay)
        let before = try await store.plannedStayRecords()
        try await coordinator.create(stay)

        #expect(try await store.plannedStayRecords() == before)
    }

    @Test func createRetryCannotOverwriteAnEditOrRestoreADeletedIdentity() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let original = try PlannedStayTestSupport.stay()
        let edited = try PlannedStayTestSupport.stay(id: original.id, region: .california)
        try await coordinator.create(original)
        try await coordinator.update(edited)

        await #expect(throws: PlannedStayCoordinator.PlanningError.stayAlreadyExists) {
            try await coordinator.create(original)
        }
        #expect(try await coordinator.snapshot().stays == [edited])
        try await coordinator.delete(stayID: original.id)
        await #expect(throws: PlannedStayCoordinator.PlanningError.stayAlreadyExists) {
            try await coordinator.create(original)
        }
        #expect(try await coordinator.snapshot().stays.isEmpty)
    }

    @Test func historicalSelectionDefeatsAnOlderSyncedHomeChoice() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let remote = try HomeRegionRecord(
            id: UUID(),
            region: .california,
            updatedAt: Self.now.addingTimeInterval(60),
        )
        try await store.perform { try await store.restoreHomeRegionRecord(remote) }
        try await coordinator.setHomeRegion(nil)
        let tombstone = try #require(await store.homeRegionRecords().first)
        #expect(tombstone.updatedAt > remote.updatedAt)
        #expect(tombstone.region == nil)
        try await store.perform { try await store.restoreHomeRegionRecord(remote) }

        #expect(try await coordinator.snapshot().homeRegion == nil)
    }

    @Test func homeAndUntrackedDestinationsDoNotChangeTrackingOrRecordedHistory() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        let texas = try #require(Region(rawValue: "us-TX"))
        let tracking = try await store.trackedRegions()
        let stay = try PlannedStayTestSupport.stay(region: texas)
        try await coordinator.create(stay)
        try await coordinator.setHomeRegion(texas)

        #expect(try await coordinator.snapshot().homeRegion == texas)
        try await coordinator.setHomeRegion(.california)
        try await coordinator.setHomeRegion(nil)
        #expect(try await coordinator.snapshot().stays == [stay])
        #expect(try await store.trackedRegions() == tracking)
        #expect(try await store.allManualDays().isEmpty)
        #expect(try await store.allSamples().isEmpty)
    }

    @Test func resetClearsBothPlanningRegisters() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)
        try await coordinator.create(PlannedStayTestSupport.stay())
        try await coordinator.setHomeRegion(.california)
        try await store.perform {
            _ = try await store.rotateDataGeneration(
                reason: .accountReset,
                changedBy: .init(rawValue: UUID()),
                at: Self.now,
            )
        }

        let snapshot = try await coordinator.snapshot()
        #expect(snapshot.stays.isEmpty)
        #expect(snapshot.homeRegion == nil)
        #expect(try await store.plannedStayRecords().isEmpty)
        #expect(try await store.homeRegionRecords().isEmpty)
    }

    @Test func homeRejectsTheUnattributedOtherRegion() async throws {
        let store = try SwiftDataStore.inMemory()
        let coordinator = Self.coordinator(store: store)

        await #expect(throws: PlannedStay.ValidationError.unsupportedRegion) {
            try await coordinator.setHomeRegion(.other)
        }
        #expect(try await store.homeRegionRecords().isEmpty)
    }
}
