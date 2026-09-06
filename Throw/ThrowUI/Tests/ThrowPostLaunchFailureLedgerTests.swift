import Testing
import ThrowCore
@testable import ThrowUI

struct ThrowPostLaunchFailureLedgerTests {
    @Test func recordingReplacesOnlyTheMatchingOwner() {
        let ledger = ThrowPostLaunchFailureLedger()
            .recording(.location(.gpsFixRequired))
            .recording(.aircraftSource)
            .recording(.location(.persistence))

        #expect(ledger.failure(for: .location) == .location(.persistence))
        #expect(ledger.failure(for: .aircraftSource) == .aircraftSource)
        #expect(ledger.failures.count == 2)
    }

    @Test func resolvingOneOwnerPreservesEveryOtherOwner() {
        let ledger = ThrowPostLaunchFailureLedger()
            .recording(.preferencePersistence)
            .recording(.aircraftSource)
            .recording(.location(.persistence))
            .recording(.playlist(.invalidDwellDuration))
            .resolving(.preferencePersistence)

        #expect(ledger.failure(for: .preferencePersistence) == nil)
        #expect(ledger.failure(for: .aircraftSource) == .aircraftSource)
        #expect(ledger.failure(for: .location) == .location(.persistence))
        #expect(ledger.failure(for: .playlist) == .playlist(.invalidDwellDuration))
    }

    @Test func failuresHaveAStableOwnerOrder() {
        let ledger = ThrowPostLaunchFailureLedger()
            .recording(.projectionRendering)
            .recording(.playlist(nil))
            .recording(.rapidAPICredential)

        #expect(ledger.failures.map(\.owner) == [
            .rapidAPICredential,
            .playlist,
            .projectionRendering,
        ])
    }
}
