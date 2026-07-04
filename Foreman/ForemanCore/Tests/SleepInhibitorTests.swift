@_spi(Testing) import ForemanCore
import Testing

@MainActor
struct SleepInhibitorTests {
    @Test func activationIsIdempotentPerDirection() {
        var begins = 0
        var ends = 0
        let inhibitor = SleepInhibitor(onBegin: { begins += 1 }, onEnd: { ends += 1 })

        #expect(!inhibitor.isActive)

        inhibitor.setActive(true, reason: "test")
        inhibitor.setActive(true, reason: "test")
        #expect(inhibitor.isActive)
        #expect(begins == 1)
        #expect(ends == 0)

        inhibitor.setActive(false, reason: "test")
        inhibitor.setActive(false, reason: "test")
        #expect(!inhibitor.isActive)
        #expect(begins == 1)
        #expect(ends == 1)
    }

    @Test func deactivatingWithoutActivatingIsANoOp() {
        var ends = 0
        let inhibitor = SleepInhibitor(onBegin: {}, onEnd: { ends += 1 })

        inhibitor.setActive(false, reason: "test")

        #expect(ends == 0)
        #expect(!inhibitor.isActive)
    }
}
