import Foundation
import Testing
@testable import WhereCore

struct ServicesStateMachineTests {
    @Test("Tracking enable then disable settles at quiescence (Coalesced.cfg)")
    func trackingEnableDisableCoalesced() {
        let result = ServicesMachineReplay.runToQuiescence(events: [
            .setTrackingDesired(true),
            .setTrackingDesired(false),
        ])

        let final = result.final.tracking
        #expect(final.desired == false)
        #expect(final.persisted == false)
        #expect(final.ingestorActive == false)
        #expect(final.published == false)
        #expect(final.worker == .idle)
    }

    @Test("Tracking enable settles published true when authorized")
    func trackingEnablePublished() {
        let result = ServicesMachineReplay.runToQuiescence(events: [
            .setTrackingDesired(true),
        ])

        let final = result.final.tracking
        #expect(final.published == true)
        #expect(final.ingestorActive == true)
    }

    @Test("Post-write manual day pings changes only after fan-out (Current.cfg)")
    func postWriteManualDayOrdering() {
        var snapshot = ServicesSnapshot.initial

        let begin = ServicesMachine.reduce(snapshot, .beginWrite)
        snapshot = begin.snapshot

        let commit = ServicesMachine.reduce(snapshot, .writeCommitted(.dayDataChanged))
        snapshot = commit.snapshot
        #expect(snapshot.postWrite.writePhase == .committed)
        #expect(snapshot.postWrite.reconcilePhase == .running)
        #expect(snapshot.postWrite.changesPinged == false)

        let quiescent = ServicesMachineReplay.runToQuiescence(events: [
            .beginWrite,
            .writeCommitted(.dayDataChanged),
        ])
        let final = quiescent.final.postWrite
        #expect(final.reconcilePhase == .done)
        #expect(final.changesPinged == true)
        #expect(final.sideEffectsApplied == true)
    }

    @Test("Reset quiesces ingestor before erase")
    func resetQuiesceOrdering() {
        let result = ServicesMachineReplay.runToQuiescence(events: [
            .resetRequested,
        ])

        let final = result.final
        #expect(final.reset.phase == .done)
        #expect(final.ingestor.quiescePhase == .done)
        #expect(final.ingestor.acceptsSamples == false)
        #expect(result.effects.contains(.beginIngestorQuiesce))
        #expect(result.effects.contains(.eraseAllData))
    }

    @Test("Launch drive runs foreground steps in order")
    func launchDriveSequence() {
        let result = ServicesMachineReplay.runToQuiescence(events: [
            .launchDriveStarted,
        ])

        #expect(result.final.launch.phase == .ready)
        #expect(result.final.launch.syncAuthRuns == 1)
        #expect(result.final.launch.reconcileRuns == 1)
        #expect(result.effects.first == .syncAuthorization)
    }

    @Test("Composite snapshot exposes every lane at once")
    func compositeSnapshotShape() {
        let snapshot = ServicesSnapshot.initial
        #expect(snapshot.tracking.worker == .idle)
        #expect(snapshot.postWrite.writePhase == .idle)
        #expect(snapshot.ingestor.quiescePhase == .idle)
        #expect(snapshot.launch.phase == .notStarted)
        #expect(snapshot.reset.phase == .idle)
    }
}
