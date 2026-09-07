import Foundation
import Testing
import ThrowCore
@_spi(Testing) @testable import ThrowUI

@MainActor
struct QuietHoursSettingsModelTests {
    @Test func equalEndpointsKeepTheLastValidatedScheduleActiveAndPersisted() async throws {
        let session = ThrowSession.fixture()
        let now = session.dateProvider.now()
        let startComponents = session.calendar.dateComponents(
            [.hour, .minute],
            from: now.addingTimeInterval(-3600),
        )
        let endComponents = session.calendar.dateComponents(
            [.hour, .minute],
            from: now.addingTimeInterval(3600),
        )
        let startHour = try #require(startComponents.hour)
        let startMinute = try #require(startComponents.minute)
        let endHour = try #require(endComponents.hour)
        let endMinute = try #require(endComponents.minute)
        let expectedSchedule = try QuietSchedule(
            start: LocalTime(
                hour: startHour,
                minute: startMinute,
            ),
            end: LocalTime(
                hour: endHour,
                minute: endMinute,
            ),
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
