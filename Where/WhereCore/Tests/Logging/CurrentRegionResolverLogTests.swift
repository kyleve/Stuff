import PeriscopeCore
import Testing
@testable import WhereCore

struct CurrentRegionResolverLogTests {
    @Test func finishedEventExportsOnlyBoundedNonLocationFields() {
        let event = CurrentRegionResolverLog.finished(
            reason: .boundaryUncertainty,
            ageBucket: .recent,
            accuracyBucket: .kilometer,
        )

        #expect(event.remoteFields.map(\.key) == [
            RemoteLogFieldKey("kind"),
            RemoteLogFieldKey("reason"),
            RemoteLogFieldKey("age_bucket"),
            RemoteLogFieldKey("accuracy_bucket"),
        ])
        #expect(event.message.contains("boundary-uncertainty"))
        #expect(event.message.contains("11-60s"))
        #expect(event.message.contains("101-1000m"))
        #expect(event.message.contains("latitude") == false)
        #expect(event.message.contains("longitude") == false)
    }
}
