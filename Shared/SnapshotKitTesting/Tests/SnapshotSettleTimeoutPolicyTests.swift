import SnapshotKit
@_spi(Testing) import SnapshotKitTesting
import Testing

struct SnapshotSettleTimeoutPolicyTests {
    @Test func missingValueKeepsLocalTimeoutsUnscaled() throws {
        let policy = try SnapshotSettleTimeoutPolicy.parse(nil)

        #expect(policy.multiplier == 1)
        #expect(policy.maximumDuration(for: .settled) == 2.5)
        #expect(policy.maximumDuration(for: .settledAtLeast(minDuration: 1.5)) == 4)
    }

    @Test func validMultiplierScalesOnlyTheMaximumBudget() throws {
        let policy = try SnapshotSettleTimeoutPolicy.parse("2")

        #expect(policy.multiplier == 2)
        #expect(policy.maximumDuration(for: .settled) == 5)
        #expect(policy.maximumDuration(for: .settledAtLeast(minDuration: 1.5)) == 8)
    }

    @Test(arguments: ["", "0", "0.5", "5", "nan", "infinity", "slow"])
    func invalidMultiplierFailsSetup(value: String) {
        #expect(throws: SnapshotRenderingError.invalidSettleTimeoutMultiplier(value: value)) {
            try SnapshotSettleTimeoutPolicy.parse(value)
        }
    }
}
