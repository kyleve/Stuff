import Foundation
import PeriscopeCore
import Testing

struct ClassifiedLogFieldTests {
    @Test func capturesOptionalOriginalErrorAndPreservesAbsence() {
        let original: (any Error)? = LogErrorTestFailure()
        let event = LogErrorTestLog.OptionalFailure(error: .restricted(.errorDetails, original))
        #expect(event.error == LogError(capturing: LogErrorTestFailure()))
        let absent: (any Error)? = nil
        let missing = LogErrorTestLog.OptionalFailure(error: .restricted(.errorDetails, absent))
        #expect(missing.error == nil)
        #expect(LogErrorTestLog.OptionalFailure(error: .restricted(.errorDetails, nil))
            .error == nil)
        #expect(missing.classifiedFields == [.restricted(
            key: LogFieldKey("error"),
            kind: .errorDetails,
        )])
    }

    @Test func acceptsOptionalSnapshotWithoutRecapturing() {
        let snapshot: LogError? = LogError(
            capturing: LogErrorTestFailure(),
            details: .object(["attempt": .int(3)]),
        )
        #expect(LogErrorTestLog.OptionalFailure(error: .restricted(.errorDetails, snapshot))
            .error == snapshot)
    }

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
