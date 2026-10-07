import Foundation
import Testing
@_spi(Testing) @testable import WhereCore

struct DataCompatibilityRuntimeTests {
    @Test func recoveryRepublishesWidgetsWithinTheFreshnessWindow() async throws {
        let world = try CompatibilityOutputTestSupport.makeWorld()
        let now = WhereCoreTestSupport.iso("2026-03-15T12:00:00-07:00")
        let services = WhereServices(
            store: world.store,
            compatibilityServices: world.services,
            locationSource: ScriptedLocationSource(),
            now: { now },
        )
        await services.widgets.refreshIfStale()
        #expect(await world.widgets.snapshots.count == 1)

        // Verification can recover without a store mutation or recording ingest to republish.
        await services.compatibilityRuntime.suspend()
        #expect(await world.widgets.compatibility.last?.allowsData == false)
        await services.widgets.refreshIfStale()

        #expect(await world.widgets.snapshots.count == 2)
        #expect(await world.widgets.compatibility.last?.allowsData == true)
    }
}
