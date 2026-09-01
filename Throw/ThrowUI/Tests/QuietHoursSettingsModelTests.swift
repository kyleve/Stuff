import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct QuietHoursSettingsModelTests {
    @Test func equalEndpointsKeepTheLastValidatedScheduleActiveAndPersisted() async throws {
        let session = ThrowSession.fixture()
        let expectedSchedule = try QuietSchedule(
            start: LocalTime(hour: 10, minute: 0),
            end: LocalTime(hour: 12, minute: 0),
        )
        session.updateQuietSchedule(expectedSchedule)
        await session.flushPreferencesSave()
        let model = QuietHoursSettingsModel(session: session)

        model.end = model.start

        #expect(model.scheduleIsValid == false)
        #expect(session.quietSchedule == expectedSchedule)
        #expect(session.isQuietNow)
        let persistedPreferences = try await session.preferenceStore.load()
        #expect(persistedPreferences.quietSchedule == expectedSchedule)
    }
}
