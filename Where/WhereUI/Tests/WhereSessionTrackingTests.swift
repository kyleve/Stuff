import Foundation
import TestHostSupport
import Testing
@_spi(Testing) import WhereCore
import WhereUI

/// Covers the launch-time reconciliation that fixes the "toggle is always off"
/// and "Grant does nothing" bugs: tracking and the authorization indicator must
/// reflect real authorization + persisted intent, not just the last tap.
@MainActor
struct WhereSessionTrackingTests {
    private func makePreferences() -> WherePreferences {
        WherePreferences(store: InMemoryKeyValueStore())
    }

    private func makeSession(
        status: LocationAuthorizationStatus,
        preferences: WherePreferences,
    ) throws -> (WhereSession, ScriptedLocationSource) {
        let source = ScriptedLocationSource(authorizationStatus: status)
        let services = try WhereServices(
            store: SwiftDataStore.inMemory(),
            locationSource: source,
            reminderScheduler: NoopLoggingReminderScheduler(),
            summaryScheduler: NoopDailySummaryScheduler(),
            issueAlertScheduler: NoopDataIssueAlertScheduler(),
            widgetRefresher: NoopWidgetTimelineRefresher(),
        )
        let session = WhereSession(services: services, preferences: preferences)
        return (session, source)
    }

    @Test func launchWithAlwaysResumesTracking() async throws {
        let (session, _) = try makeSession(status: .always, preferences: makePreferences())
        await session.start()
        #expect(session.authorizationStatus == .always)
        #expect(session.isTracking)
        #expect(!session.permissionDenied)
    }

    @Test func launchWithWhenInUseDoesNotTrack() async throws {
        let (session, _) = try makeSession(status: .whenInUse, preferences: makePreferences())
        await session.start()
        #expect(session.authorizationStatus == .whenInUse)
        #expect(!session.isTracking)
    }

    @Test func launchWithDeniedDoesNotTrackOrAlert() async throws {
        let (session, _) = try makeSession(status: .denied, preferences: makePreferences())
        await session.start()
        #expect(session.authorizationStatus == .denied)
        #expect(!session.isTracking)
        // Launch must not pop the Settings alert; that's reserved for taps.
        #expect(!session.permissionDenied)
    }

    @Test func stoppingTrackingPersistsAcrossLaunches() async throws {
        let preferences = makePreferences()
        let (session, _) = try makeSession(status: .always, preferences: preferences)
        await session.start()
        #expect(session.isTracking)

        await session.stopTracking()
        #expect(!session.isTracking)

        // A fresh session sharing the same preferences should stay paused even
        // though authorization is still Always.
        let (relaunched, _) = try makeSession(status: .always, preferences: preferences)
        await relaunched.start()
        #expect(!relaunched.isTracking)
    }

    @Test func grantingLaterStartsTrackingViaLiveUpdates() async throws {
        let (session, source) = try makeSession(
            status: .notDetermined,
            preferences: makePreferences(),
        )
        await session.start()
        #expect(!session.isTracking)

        // Simulate the user granting Always in the system prompt / Settings.
        source.emitAuthorization(.always)

        await waitUntil { session.isTracking }
        #expect(session.authorizationStatus == .always)
        #expect(session.isTracking)
    }

    /// Guards against a retain cycle through the long-lived authorization
    /// observer: it captures `[weak self]` and `deinit` cancels it, so dropping
    /// the last strong reference must deallocate the session even while the
    /// observer task is parked awaiting updates.
    @Test func deinitsWhileObservingAuthorization() async throws {
        weak var weakSession: WhereSession?
        do {
            let (session, _) = try makeSession(status: .always, preferences: makePreferences())
            weakSession = session
            // start() spins up the long-lived authorization observer; once it
            // returns the task is parked in `for await` (ScriptedLocationSource
            // emits nothing on its own) holding only a weak self.
            await session.start()
            #expect(weakSession != nil)
        }
        #expect(weakSession == nil)
    }

    private func waitUntil(
        timeout: Duration = .seconds(2),
        _ predicate: () -> Bool,
    ) async {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(5))
        }
        #expect(predicate(), "condition was not met before timeout")
    }
}
