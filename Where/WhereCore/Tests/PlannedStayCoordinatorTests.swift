import Foundation
import RegionKit
import SwiftData
import Testing
@testable import WhereCore

struct PlannedStayCoordinatorTests {
    private static let now = Date(timeIntervalSince1970: 1_780_000_000)

    private static func coordinator(
        store: SwiftDataStore,
        author: RecordingDeviceID = WhereCoreTestSupport.authorID,
    ) -> PlannedStayCoordinator {
        PlannedStayCoordinator(store: store, currentDeviceID: author, now: { now })
    }

    @Test func offlineEditsKeepWinningDeviceThroughReplay() async throws {
        let phone = RecordingDeviceID(rawValue: UUID())
        let tablet = RecordingDeviceID(rawValue: UUID())
        let origin = try SwiftDataStore.inMemory()
        let other = try SwiftDataStore.inMemory()
        let writerA = Self.coordinator(store: origin, author: phone)
        let writerB = Self.coordinator(store: other, author: tablet)
        let planned = try PlannedStayTestSupport.stay()
        try await writerA.create(planned)
        try await writerA.setHomeRegion(.newYork)
        let originalStay = try #require(await origin.plannedStayRecords().first)
        let originalHome = try #require(await origin.homeRegionRecords().first)
        #expect(originalStay.changedByDeviceID == phone)
        #expect(originalHome.changedByDeviceID == phone)
        try await other.perform {
            try await other.restorePlannedStayRecord(originalStay)
            try await other.restoreHomeRegionRecord(originalHome)
        }

        let updated = try PlannedStayTestSupport.stay(id: planned.id, region: .california)
        try await writerA.update(updated)
        try await writerA.setHomeRegion(.california)
        try await writerB.delete(stayID: planned.id)
        try await writerB.setHomeRegion(nil)
        let edit = try #require(await origin.plannedStayRecords().first)
        let updatedHome = try #require(await origin.homeRegionRecords().first)
        let deleted = try #require(await other.plannedStayRecords().first)
        let clearedHome = try #require(await other.homeRegionRecords().first)
        #expect(edit.value == updated && edit.changedByDeviceID == phone)
        #expect(updatedHome.region == .california && updatedHome.changedByDeviceID == phone)
        #expect(deleted.value == nil && deleted.changedByDeviceID == tablet)
        #expect(clearedHome.region == nil && clearedHome.changedByDeviceID == tablet)
        #expect(edit.updatedAt == deleted.updatedAt)
        #expect(updatedHome.updatedAt == clearedHome.updatedAt)

        for reverseDelivery in [false, true] {
            let reader = try SwiftDataStore.inMemory()
            let stays = reverseDelivery ? [deleted, edit] : [edit, deleted]
            let homes = reverseDelivery ? [clearedHome, updatedHome] : [updatedHome, clearedHome]
            try await reader.perform {
                for record in stays + [edit] {
                    try await reader.restorePlannedStayRecord(record)
                }
                for record in homes + [clearedHome] {
                    try await reader.restoreHomeRegionRecord(record)
                }
            }
            #expect(try await Set(reader.plannedStayRecords()) == Set(stays))
            #expect(try await Set(reader.homeRegionRecords()) == Set(homes))
            let winner = edit.id.uuidString > deleted.id.uuidString ? edit : deleted
            let homeWinner = updatedHome.id.uuidString > clearedHome.id
                .uuidString ? updatedHome : clearedHome
            let projection = try await Self.coordinator(store: reader).snapshot()
            #expect(projection.stays == [winner.value].compactMap(\.self))
            #expect(projection.homeRegion == homeWinner.region)

            let conflictingStay = try PlannedStayRecord(
                id: edit.id,
                stayID: edit.stayID,
                value: edit.value,
                updatedAt: edit.updatedAt,
                changedByDeviceID: tablet,
            )
            let conflictingHome = try HomeRegionRecord(
                id: clearedHome.id,
                region: clearedHome.region,
                updatedAt: clearedHome.updatedAt,
                changedByDeviceID: phone,
            )
            await #expect(throws: ActionAttributionError.conflictingAuthor) {
                try await reader
                    .perform { try await reader.restorePlannedStayRecord(conflictingStay) }
            }
            await #expect(throws: ActionAttributionError.conflictingAuthor) {
                try await reader
                    .perform { try await reader.restoreHomeRegionRecord(conflictingHome) }
            }
            #expect(try await Set(reader.plannedStayRecords()) == Set(stays))
            #expect(try await Set(reader.homeRegionRecords()) == Set(homes))
        }
    }

    enum MirroredRevision: CaseIterable { case identical, otherAuthor, otherValue }

    @Test(arguments: MirroredRevision.allCases, [false, true])
    func readsOfMirroredRowsRequireImmutablePlanningRevisions(
        duplicate: MirroredRevision,
        reverseDelivery: Bool,
    ) async throws {
        let container = try SwiftDataStore.makeContainer(storage: .inMemory)
        let remote = ModelContext(container)
        let author = WhereCoreTestSupport.authorID
        let secondAuthor = duplicate == .otherAuthor ? RecordingDeviceID(rawValue: UUID()) : author
        let value = try PlannedStayTestSupport.stay()
        let original = try PlannedStayRecord(
            id: UUID(),
            stayID: value.id,
            value: value,
            updatedAt: Self.now,
            changedByDeviceID: author,
        )
        let second = try PlannedStayRecord(
            id: original.id,
            stayID: value.id,
            value: duplicate == .otherValue ? nil : value,
            updatedAt: Self.now,
            changedByDeviceID: secondAuthor,
        )
        let home = try HomeRegionRecord(
            id: UUID(),
            region: .newYork,
            updatedAt: Self.now,
            changedByDeviceID: author,
        )
        let otherHome = try HomeRegionRecord(
            id: home.id,
            region: duplicate == .otherValue ? nil : .newYork,
            updatedAt: Self.now,
            changedByDeviceID: secondAuthor,
        )
        for row in reverseDelivery ? [second, original] : [original, second] {
            remote.insert(SDPlannedStay(value: row, generationID: .initial))
        }
        for row in reverseDelivery ? [otherHome, home] : [home, otherHome] {
            remote.insert(SDHomeRegion(value: row, generationID: .initial))
        }
        try remote.save()
        let store = SwiftDataStore(modelContainer: container)
        if duplicate == .identical {
            #expect(try await store.plannedStayRecords() == [original])
            #expect(try await store.homeRegionRecords() == [home])
        } else {
            await #expect(throws: ActionAttributionError.conflictingAuthor) {
                try await store.plannedStayRecords()
            }
            await #expect(throws: ActionAttributionError.conflictingAuthor) {
                try await store.homeRegionRecords()
            }
        }
    }

    @Test func localReplacementRejectsAReusedRevisionIDBeforeDeletingRows() async throws {
        let store = try SwiftDataStore.inMemory()
        let author = WhereCoreTestSupport.authorID
        let first = try PlannedStayTestSupport.record(stay: PlannedStayTestSupport.stay())
        let other = try PlannedStayTestSupport.record(stay: PlannedStayTestSupport.stay())
        let home = try HomeRegionRecord(
            id: UUID(),
            region: .california,
            updatedAt: Self.now,
            changedByDeviceID: author,
        )
        let conflicting = try PlannedStayRecord(
            id: first.id,
            stayID: other.stayID,
            value: nil,
            updatedAt: first.updatedAt,
            changedByDeviceID: author,
        )
        let conflictingHome = try HomeRegionRecord(
            id: home.id,
            region: home.region,
            updatedAt: home.updatedAt,
            changedByDeviceID: .init(rawValue: UUID()),
        )
        try await store.perform {
            try await store.restorePlannedStayRecord(first)
            try await store.restorePlannedStayRecord(other)
            try await store.restoreHomeRegionRecord(home)
        }
        await #expect(throws: ActionAttributionError.conflictingAuthor) {
            try await store.perform { try await store.replacePlannedStayRecord(with: conflicting) }
        }
        await #expect(throws: ActionAttributionError.conflictingAuthor) {
            try await store
                .perform { try await store.replaceHomeRegionRecord(with: conflictingHome) }
        }
        #expect(try await Set(store.plannedStayRecords()) == [first, other])
        #expect(try await store.homeRegionRecords() == [home])
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
        let unrelated = try PlannedStayTestSupport.stay(region: .ontario)
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
            changedByDeviceID: WhereCoreTestSupport.authorID,
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
