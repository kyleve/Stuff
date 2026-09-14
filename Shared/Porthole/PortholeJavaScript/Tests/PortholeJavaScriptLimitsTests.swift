import PortholeJavaScript
import Testing

struct PortholeJavaScriptLimitsTests {
    @Test func rejectsInvalidConfigurationBeforeStartingEngine() async {
        var limits = PortholeJavaScriptLimits.interactive
        limits.heapBytes = 0
        let session = PortholeJavaScriptSession(
            limits: limits,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        await #expect(throws: PortholeJavaScriptError.invalidConfiguration) {
            try await session.execute(source: "1")
        }
    }

    @Test func boundsSourceBytes() async {
        var limits = PortholeJavaScriptLimits.interactive
        limits.sourceBytes = 4
        let session = PortholeJavaScriptSession(
            limits: limits,
            nativeCall: { _, value in value },
            events: { _ in },
        )
        await #expect(throws: PortholeJavaScriptError.sourceTooLarge) {
            try await session.execute(source: "'hello'")
        }
    }
}
