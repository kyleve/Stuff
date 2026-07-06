import LogKit
import Testing
@testable import WhereCore

@Test
func channelUsesSharedSubsystemAndCategory() throws {
    let store = LogStore()
    let channel = LogChannel(
        subsystem: WhereLog.subsystem,
        category: WhereLog.Category.locationIngestor.rawValue,
        store: store,
    )
    channel.error("boom")

    let entry = try #require(store.snapshot().first)
    #expect(entry.subsystem == "com.stuff.where")
    #expect(entry.category == "LocationIngestor")
}

@Test
func categoryRawValuesMatchTypeNames() {
    // Raw values must stay equal to the historical os.Logger category strings
    // so Console.app filters keep working after the migration.
    #expect(WhereLog.Category.swiftDataStore.rawValue == "SwiftDataStore")
    #expect(WhereLog.Category.widgetRefresher.rawValue == "WidgetRefresher")
    #expect(WhereLog.Category.allCases.count == 19)
}

@Test
func channelFactoryRecordsIntoSharedStore() {
    let before = WhereLog.store.snapshot().count
    WhereLog.channel(.backupService).info("wrote backup")
    #expect(WhereLog.store.snapshot().count == before + 1)
}
