import Foundation
import PeriscopeCore
import Testing

struct ClassifiedLogFieldTests {
    @Test func capturesOriginalErrorIntoRestrictedInput() {
        let original = NSError(
            domain: "Example",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Unavailable"],
        )
        let event = LogErrorTestLog.Failed(error: .restricted(.errorDetails, original))
        #expect(event.error == LogError(capturing: original))
        #expect(event.message == "Failed: Unavailable")
        #expect(event.classifiedFields == [.restricted(
            key: LogFieldKey("error"),
            kind: .errorDetails,
        )])
    }

    @Test func acceptsExplicitSnapshotWithoutRecapturing() {
        let snapshot = LogError(
            capturing: LogErrorTestFailure(),
            details: .object(["attempt": .int(3)]),
        )
        let event = LogErrorTestLog.Failed(error: .restricted(.errorDetails, snapshot))
        #expect(event.error == snapshot)
    }
}
