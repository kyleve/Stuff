import PeriscopeCore
import Testing
@testable import WhereUI

struct WhereSessionLogTests {
    @Test func everyEventCaseExportsADistinctSafeKind() {
        let events: [WhereSessionLog] = [
            .whenInUseOnly,
            .locationAccessDenied(status: "private status"),
            .backgroundTrackingStarted,
            .backgroundTrackingStopped,
            .permissionGranted(status: "private status"),
            .trackingEnabled,
            .stoppedBackgroundTracking,
            .recordingReconcileFailed(description: "private error"),
            .remindersUnauthorized,
            .summaryUnauthorized,
            .issueAlertsUnauthorized,
            .regionStylesLoadFailed(description: "private error"),
            .erasedSession,
        ]

        let kinds = events.compactMap(remoteKind)
        #expect(kinds.count == events.count)
        #expect(Set(kinds).count == events.count)
        #expect(kinds.contains("private status") == false)
        #expect(kinds.contains("private error") == false)
    }

    private func remoteKind(_ event: WhereSessionLog) -> String? {
        guard let field = event.remoteFields.first,
              field.key == RemoteLogFieldKey("kind"),
              case let .category(category) = field.value
        else { return nil }
        return category.rawValue
    }
}
