import Testing
@testable import WhereUI

struct WhereSessionLogTests {
    @Test func everyEventHasAStableDistinctName() {
        let names = [
            WhereSessionLog.WhenInUseOnly.eventName,
            WhereSessionLog.LocationAccessDenied.eventName,
            WhereSessionLog.BackgroundTrackingStarted.eventName,
            WhereSessionLog.BackgroundTrackingStopped.eventName,
            WhereSessionLog.PermissionGranted.eventName,
            WhereSessionLog.TrackingEnabled.eventName,
            WhereSessionLog.StoppedBackgroundTracking.eventName,
            WhereSessionLog.RecordingReconcileFailed.eventName,
            WhereSessionLog.RemindersUnauthorized.eventName,
            WhereSessionLog.SummaryUnauthorized.eventName,
            WhereSessionLog.IssueAlertsUnauthorized.eventName,
            WhereSessionLog.RegionStylesLoadFailed.eventName,
            WhereSessionLog.ErasedSession.eventName,
        ]
        #expect(Set(names).count == names.count)
        #expect(names.allSatisfy { $0.hasPrefix("WhereSession.") })
    }
}
