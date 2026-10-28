import PeriscopeCore
import Testing
@testable import WhereCore

struct CurrentRegionResolverLogTests {
    @Test func finishedEventExportsOnlyBoundedNonLocationFields() {
        let event = CurrentRegionResolverLog.Finished(
            reason: .shared(.category, .boundaryUncertainty),
            ageBucket: .shared(.category, .recent),
            accuracyBucket: .shared(.category, .kilometer),
        )

        #expect(event.classifiedFields == [
            .shareable(
                key: LogFieldKey("reason"),
                kind: .category,
                value: .string("boundary-uncertainty"),
            ),
            .shareable(
                key: LogFieldKey("age_bucket"),
                kind: .category,
                value: .string("11-60s"),
            ),
            .shareable(
                key: LogFieldKey("accuracy_bucket"),
                kind: .category,
                value: .string("101-1000m"),
            ),
        ])
        #expect(CurrentRegionResolverLog.Finished.eventName == "CurrentRegionResolver.finished")
        #expect(event.message.contains("boundary-uncertainty"))
        #expect(event.message.contains("11-60s"))
        #expect(event.message.contains("101-1000m"))
        #expect(event.message.contains("latitude") == false)
        #expect(event.message.contains("longitude") == false)
    }
}
