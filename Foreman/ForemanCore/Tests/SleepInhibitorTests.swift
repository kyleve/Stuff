@_spi(Testing) import ForemanCore
import Testing

@MainActor
struct SleepInhibitorTests {
    @Test func activationIsIdempotentPerDirection() {
        let recorder = SleepAssertionRecorder()
        let inhibitor = SleepInhibitor(backend: recorder)

        #expect(!inhibitor.isActive)

        inhibitor.setActive(true, reason: "test")
        inhibitor.setActive(true, reason: "test")
        #expect(inhibitor.isActive)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 0)

        inhibitor.setActive(false, reason: "test")
        inhibitor.setActive(false, reason: "test")
        #expect(!inhibitor.isActive)
        #expect(recorder.begins == 1)
        #expect(recorder.ends == 1)
    }

    @Test func deactivatingWithoutActivatingIsANoOp() {
        let recorder = SleepAssertionRecorder()
        let inhibitor = SleepInhibitor(backend: recorder)

        inhibitor.setActive(false, reason: "test")

        #expect(recorder.ends == 0)
        #expect(!inhibitor.isActive)
    }
}
