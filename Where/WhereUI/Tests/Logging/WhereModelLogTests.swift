import PeriscopeCore
import Testing
@testable import WhereUI

struct WhereModelLogTests {
    @Test func everyEventCaseExportsADistinctSafeKind() {
        let events: [WhereModelLog] = [
            .onboardingCompleted,
            .openedRealScope,
            .startedSession(year: 2026),
            .endedSession,
            .resetPreferences,
            .enteredDemoMode,
            .exitedDemoMode,
        ]

        let kinds = events.compactMap(remoteKind)
        #expect(kinds.count == events.count)
        #expect(Set(kinds).count == events.count)
        #expect(kinds.contains("2026") == false)
    }

    private func remoteKind(_ event: WhereModelLog) -> String? {
        guard let field = event.remoteFields.first,
              field.key == RemoteLogFieldKey("kind"),
              case let .category(category) = field.value
        else { return nil }
        return category.rawValue
    }
}
