import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct TransitRuntimeTests {
    @Test func validEmptyPartitionMakesActivationReady() async throws {
        let fixture = try Fixture()
        let runtime = fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.emptySnapshot(partition: fixture.partitionA)],
            failed: [],
        ))
        let activationLease = lease(7)
        _ = await runtime.stateUpdates()
        _ = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(1),
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        let update = await runtime.currentUpdate()
        #expect(update.health == .healthy(lastUpdate: fixture.date, visibleContentCount: 0))
        #expect(update.experienceFrame.experienceID == .transit)
        await runtime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func partialPartitionFailureKeepsFreshPartitionAndReportsRetrying() async throws {
        let fixture = try Fixture()
        let runtime = try fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.runSnapshot()],
            failed: [fixture.partitionB],
        ))
        let activationLease = lease(9)
        _ = await runtime.stateUpdates()
        _ = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(1),
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        let update = await runtime.currentUpdate()
        guard case let .retrying(_, _, failure, visibleCount) = update.health else {
            Issue.record("Expected partial service to remain visible with retrying health")
            return
        }
        #expect(failure == .transport)
        #expect(visibleCount == 1)
        #expect(update.experienceFrame.transitFrame?.network != nil)
        #expect(update.experienceFrame.transitFrame?.vehicles != nil)
        await runtime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func suspensionRetainsLeaseAndRequiresNewerDemand() async throws {
        let fixture = try Fixture()
        let runtime = fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.emptySnapshot(partition: fixture.partitionA)],
            failed: [],
        ))
        let activationLease = lease(21)
        _ = await runtime.stateUpdates()

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(1),
        ) else {
            Issue.record("The first polling demand must be accepted")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        let ready = await runtime.currentUpdate()
        #expect(ready.experienceFrame.transitFrame?.network != nil)
        #expect(ready.experienceFrame.transitFrame?.vehicles != nil)

        let suspension = await runtime.suspendPolling(
            lease: activationLease,
            demandGeneration: demand(2),
            reporting: .idle,
        )
        guard case let .stopped(stopped) = suspension else {
            Issue.record("The current physical poller must stop")
            return
        }
        #expect(stopped.activationLease == activationLease)
        #expect(stopped.successfulActivationLease == nil)
        #expect(stopped.health == .idle)
        #expect(stopped.experienceFrame.transitFrame == .empty)

        let equalDemand = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(2),
        )
        guard case let .superseded(current) = equalDemand else {
            Issue.record("An equal stopped demand generation must remain tombstoned")
            return
        }
        #expect(current.activationLease == activationLease)
        #expect(current.successfulActivationLease == nil)
        #expect(current.health == .idle)
        #expect(current.experienceFrame.transitFrame == .empty)

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(3),
        ) else {
            Issue.record("A newer demand generation must resume the logical lease")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        let resumed = await runtime.currentUpdate()
        #expect(resumed.activationLease == activationLease)
        #expect(resumed.health == .healthy(lastUpdate: fixture.date, visibleContentCount: 0))
        #expect(resumed.experienceFrame.transitFrame?.network != nil)
        #expect(resumed.experienceFrame.transitFrame?.vehicles != nil)

        await runtime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func deactivationTombstonesLeaseUntilANewerGeneration() async throws {
        let fixture = try Fixture()
        let runtime = fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.emptySnapshot(partition: fixture.partitionA)],
            failed: [],
        ))
        let oldLease = lease(31)
        let replacementLease = lease(32)
        _ = await runtime.stateUpdates()

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: oldLease,
            demandGeneration: demand(1),
        ) else {
            Issue.record("The first activation must be accepted")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == oldLease
        }

        await runtime.deactivate(lease: oldLease, reporting: .idle)
        let deactivated = await runtime.currentUpdate()
        #expect(deactivated.activationLease == nil)
        #expect(deactivated.successfulActivationLease == nil)
        #expect(deactivated.health == .idle)
        #expect(deactivated.experienceFrame.transitFrame == .empty)

        let repeatedActivation = await runtime.activate(
            labelMode: .routeOnly,
            lease: oldLease,
            demandGeneration: demand(2),
        )
        guard case let .superseded(current) = repeatedActivation else {
            Issue.record("Full deactivation must tombstone an equal experience lease")
            return
        }
        #expect(current.activationLease == nil)
        #expect(current.successfulActivationLease == nil)
        #expect(current.health == .idle)
        #expect(current.experienceFrame.transitFrame == .empty)

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: replacementLease,
            demandGeneration: demand(2),
        ) else {
            Issue.record("A newer experience lease must pass the deactivation tombstone")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == replacementLease
        }

        await runtime.deactivate(lease: replacementLease, reporting: .idle)
    }

    @Test func staleQueuedDeactivationCannotStopAReplacement() async throws {
        let fixture = try Fixture()
        let runtime = fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.emptySnapshot(partition: fixture.partitionA)],
            failed: [],
        ))
        let oldLease = lease(41)
        let replacementLease = lease(42)
        let gate = TransitDeactivationGate()
        _ = await runtime.stateUpdates()

        _ = await runtime.activate(
            labelMode: .routeOnly,
            lease: oldLease,
            demandGeneration: demand(1),
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == oldLease
        }

        let staleDeactivation = Task {
            await gate.hold()
            await runtime.deactivate(lease: oldLease, reporting: .idle)
        }
        await gate.waitUntilHeld()

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: replacementLease,
            demandGeneration: demand(2),
        ) else {
            await gate.release()
            await staleDeactivation.value
            Issue.record("The replacement activation must be accepted")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == replacementLease
        }
        await gate.release()
        await staleDeactivation.value

        let update = await runtime.currentUpdate()
        #expect(update.activationLease == replacementLease)
        #expect(update.successfulActivationLease == replacementLease)
        #expect(update.health == .healthy(lastUpdate: fixture.date, visibleContentCount: 0))
        #expect(update.experienceFrame.transitFrame?.network != nil)
        #expect(update.experienceFrame.transitFrame?.vehicles != nil)

        await runtime.deactivate(lease: replacementLease, reporting: .idle)
    }

    @Test func stopInvalidatesAnActivationBeforeItInstallsPolling() async throws {
        let fixture = try Fixture()
        let runtime = fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.emptySnapshot(partition: fixture.partitionA)],
            failed: [],
        ))
        let gate = TransitActivationGate()
        let activationLease = lease(11)
        await runtime.setBeforeStartingPollingForTesting {
            await gate.hold()
        }

        let activation = Task {
            await runtime.activate(
                labelMode: .routeOnly,
                lease: activationLease,
                demandGeneration: demand(1),
            )
        }
        await gate.waitUntilHeld()

        let suspension = await runtime.suspendPolling(
            lease: activationLease,
            demandGeneration: demand(2),
            reporting: .idle,
        )
        switch suspension {
            case let .alreadyStopped(current):
                #expect(current.activationLease == activationLease)
                #expect(current.successfulActivationLease == nil)
                #expect(current.experienceFrame.transitFrame == .empty)
            case .stopped, .superseded:
                Issue.record("A stop in the activation gap must retire a logical attempt")
        }

        await gate.release()
        guard case .superseded = await activation.value else {
            Issue.record("The retired activation must not install a poller")
            return
        }
        await runtime.setBeforeStartingPollingForTesting(nil)
        guard case .superseded = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(2),
        ) else {
            Issue.record("An equal stopped demand generation must remain tombstoned")
            return
        }
        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: activationLease,
            demandGeneration: demand(3),
        ) else {
            Issue.record("A newer demand generation must restart the active lease")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        await runtime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func laterActivationSupersedesDeactivationDrainingAnOldSnapshot() async throws {
        let fixture = try Fixture()
        let snapshotGate = FirstTransitSnapshotGate()
        let runtime = fixture.runtime(source: FirstSnapshotControlledTransitObservationSource(
            snapshot: fixture.emptySnapshot(partition: fixture.partitionA),
            gate: snapshotGate,
        ))
        let oldLease = lease(51)
        let replacementLease = lease(52)
        _ = await runtime.stateUpdates()

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: oldLease,
            demandGeneration: demand(1),
        ) else {
            Issue.record("The first activation must be accepted")
            return
        }
        await snapshotGate.waitUntilHeld()

        let drainingDeactivation = Task {
            await runtime.deactivate(lease: oldLease, reporting: .idle)
        }
        do {
            try await waitUntil {
                await runtime.currentUpdate().activationLease == nil
            }

            guard case .accepted = await runtime.activate(
                labelMode: .routeOnly,
                lease: replacementLease,
                demandGeneration: demand(2),
            ) else {
                await snapshotGate.release()
                await drainingDeactivation.value
                Issue.record("The replacement activation must supersede draining teardown")
                return
            }
            try await waitUntil {
                await runtime.currentUpdate().successfulActivationLease == replacementLease
            }
        } catch {
            await snapshotGate.release()
            await drainingDeactivation.value
            throw error
        }

        let readyReplacement = await runtime.currentUpdate()
        await snapshotGate.release()
        await drainingDeactivation.value

        let update = await runtime.currentUpdate()
        #expect(update.activationLease == replacementLease)
        #expect(update.successfulActivationLease == replacementLease)
        #expect(update.health == readyReplacement.health)
        #expect(update.experienceFrame == readyReplacement.experienceFrame)

        await runtime.deactivate(lease: replacementLease, reporting: .idle)
    }

    @Test func newerLeaseWithOlderDemandIsRejectedAtomically() async throws {
        let fixture = try Fixture()
        let runtime = fixture.runtime(source: FixedTransitObservationSource(
            snapshots: [fixture.partitionA: fixture.emptySnapshot(partition: fixture.partitionA)],
            failed: [],
        ))
        let currentLease = lease(61)
        let rejectedLease = lease(62)
        _ = await runtime.stateUpdates()

        guard case .accepted = await runtime.activate(
            labelMode: .routeOnly,
            lease: currentLease,
            demandGeneration: demand(2),
        ) else {
            Issue.record("The current activation must be accepted")
            return
        }
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == currentLease
        }
        let beforeRejectedActivation = await runtime.currentUpdate()

        let rejectedActivation = await runtime.activate(
            labelMode: .routeOnly,
            lease: rejectedLease,
            demandGeneration: demand(1),
        )
        guard case let .superseded(current) = rejectedActivation else {
            Issue.record("An older demand must reject its newer lease as one transaction")
            return
        }
        #expect(current.activationLease == currentLease)
        #expect(current.successfulActivationLease == currentLease)
        #expect(current.health == beforeRejectedActivation.health)
        #expect(current.experienceFrame == beforeRejectedActivation.experienceFrame)

        let afterRejectedActivation = await runtime.currentUpdate()
        #expect(afterRejectedActivation.activationLease == currentLease)
        #expect(afterRejectedActivation.successfulActivationLease == currentLease)
        #expect(afterRejectedActivation.health == beforeRejectedActivation.health)
        #expect(afterRejectedActivation.experienceFrame == beforeRejectedActivation.experienceFrame)

        await runtime.deactivate(lease: currentLease, reporting: .idle)
    }

    private func demand(_ ordinal: Int) -> ProjectionDemandGeneration {
        precondition(ordinal >= 0)
        return (0 ..< ordinal).reduce(.initial) { generation, _ in
            generation.successor()
        }
    }

    private func lease(_ generation: UInt64) -> ProjectionActivationLease {
        ProjectionActivationLease(
            experienceID: .transit,
            generation: .init(rawValue: generation),
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await condition() == false {
            guard clock.now < deadline else { throw TransitRuntimeTestError.timedOut }
            await Task.yield()
        }
    }
}

private enum TransitRuntimeTestError: Error {
    case timedOut
}

extension ProjectionExperienceFrame {
    fileprivate var transitFrame: TransitExperienceFrame? {
        guard case let .transit(frame) = self else { return nil }
        return frame
    }
}

private struct FixedTransitScheduleSource: TransitScheduleSource {
    let value: TransitSchedule

    func schedule(fetchedAt _: Date) async throws -> TransitSchedule {
        value
    }
}

private struct FixedTransitObservationSource: TransitObservationSource {
    let snapshots: [TransitFeedPartitionID: TransitPartitionSnapshot]
    let failed: Set<TransitFeedPartitionID>

    var partitionIDs: [TransitFeedPartitionID] {
        Array(Set(snapshots.keys).union(failed)).sorted { $0.rawValue < $1.rawValue }
    }

    func snapshot(
        for partitionID: TransitFeedPartitionID,
        fetchedAt _: Date,
    ) async throws -> TransitPartitionSnapshot {
        if failed.contains(partitionID) { throw TransitDataError.unavailable }
        guard let snapshot = snapshots[partitionID] else { throw TransitDataError.unavailable }
        return snapshot
    }
}

private struct FirstSnapshotControlledTransitObservationSource: TransitObservationSource {
    let snapshotValue: TransitPartitionSnapshot
    let gate: FirstTransitSnapshotGate

    init(
        snapshot: TransitPartitionSnapshot,
        gate: FirstTransitSnapshotGate,
    ) {
        snapshotValue = snapshot
        self.gate = gate
    }

    var partitionIDs: [TransitFeedPartitionID] {
        [snapshotValue.partitionID]
    }

    func snapshot(
        for partitionID: TransitFeedPartitionID,
        fetchedAt _: Date,
    ) async throws -> TransitPartitionSnapshot {
        guard partitionID == snapshotValue.partitionID else {
            throw TransitDataError.unavailable
        }
        await gate.holdFirstSnapshot()
        return snapshotValue
    }
}

private struct SuspendedTransitClock: TransitPollingClock {
    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

private struct Fixture {
    let date = Date(timeIntervalSince1970: 1_800_000_000)
    let agency = TransitAgencyID.mtaNewYorkCityTransit
    let partitionA: TransitFeedPartitionID
    let partitionB: TransitFeedPartitionID
    let routeID: TransitRouteID
    let firstStopID: TransitStopID
    let secondStopID: TransitStopID
    let tripID: TransitTripID
    let schedule: TransitSchedule

    init() throws {
        partitionA = try #require(TransitFeedPartitionID(rawValue: "a"))
        partitionB = try #require(TransitFeedPartitionID(rawValue: "b"))
        routeID = try #require(TransitRouteID(agencyID: agency, rawValue: "A"))
        firstStopID = try #require(TransitStopID(agencyID: agency, rawValue: "A01N"))
        secondStopID = try #require(TransitStopID(agencyID: agency, rawValue: "A02N"))
        tripID = try #require(TransitTripID(agencyID: agency, rawValue: "trip-A"))
        let first = try TransitStop(
            id: firstStopID,
            name: "First",
            coordinate: GeoCoordinate(latitude: 40.70, longitude: -74.01),
        )
        let second = try TransitStop(
            id: secondStopID,
            name: "Second",
            coordinate: GeoCoordinate(latitude: 40.72, longitude: -73.99),
        )
        let color = try #require(TransitColor(hex: "0039A6"))
        schedule = TransitSchedule(
            agencyID: agency,
            revision: "fixture",
            fetchedAt: date,
            routes: [routeID: TransitRoute(id: routeID, shortName: "A", color: color)],
            stops: [firstStopID: first, secondStopID: second],
            tripPatterns: [TransitTripPattern(
                tripID: tripID,
                routeID: routeID,
                direction: 0,
                headsign: "Second",
                shapeID: "shape",
                stops: [
                    TransitTripPattern.Stop(
                        stopID: firstStopID,
                        sequence: 1,
                        arrivalSeconds: 0,
                        departureSeconds: 0,
                        shapeDistanceTraveled: 0,
                    ),
                    TransitTripPattern.Stop(
                        stopID: secondStopID,
                        sequence: 2,
                        arrivalSeconds: 120,
                        departureSeconds: 120,
                        shapeDistanceTraveled: 2,
                    ),
                ],
            )],
            shapes: ["shape": [
                TransitShapePoint(coordinate: first.coordinate, distanceTraveled: 0),
                TransitShapePoint(coordinate: second.coordinate, distanceTraveled: 2),
            ]],
        )
    }

    func runtime(source: any TransitObservationSource) -> TransitRuntime {
        TransitRuntime(
            observationSource: source,
            scheduleSource: FixedTransitScheduleSource(value: schedule),
            scheduleStore: InMemoryTransitScheduleStore(schedule: schedule),
            networkRuntime: LayerCatalog.standard.transitNetwork.runtimeFactory(),
            vehiclesRuntime: LayerCatalog.standard.transitVehicles.runtimeFactory(),
            dateProvider: FixtureDateProvider(date: date),
            clock: SuspendedTransitClock(),
        )
    }

    func emptySnapshot(partition: TransitFeedPartitionID) -> TransitPartitionSnapshot {
        TransitPartitionSnapshot(
            partitionID: partition,
            generatedAt: date,
            fetchedAt: date,
            runs: [],
        )
    }

    func runSnapshot() throws -> TransitPartitionSnapshot {
        let runID = try #require(TransitRunID(
            agencyID: agency,
            partitionID: partitionA,
            serviceDate: "20270101",
            stableRunValue: "A-101",
        ))
        return TransitPartitionSnapshot(
            partitionID: partitionA,
            generatedAt: date,
            fetchedAt: date,
            runs: [TransitRunObservation(
                id: runID,
                tripID: tripID,
                routeID: routeID,
                direction: 0,
                observedAt: date,
                upcomingStops: [TransitStopTimePrediction(
                    stopID: secondStopID,
                    arrival: date.addingTimeInterval(60),
                    departure: date.addingTimeInterval(60),
                )],
            )],
        )
    }
}

private actor TransitActivationGate {
    private var holdContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var isReleased = false

    func hold() async {
        guard isReleased == false else { return }
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            precondition(holdContinuation == nil, "Only one Transit activation can wait")
            holdContinuation = continuation
        }
    }

    func waitUntilHeld() async {
        guard holdContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        holdContinuation?.resume()
        holdContinuation = nil
    }
}

private actor TransitDeactivationGate {
    private var holdContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func hold() async {
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            precondition(holdContinuation == nil, "Only one Transit deactivation can wait")
            holdContinuation = continuation
        }
    }

    func waitUntilHeld() async {
        guard holdContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        holdContinuation?.resume()
        holdContinuation = nil
    }
}

private actor FirstTransitSnapshotGate {
    private var didHoldFirstSnapshot = false
    private var isReleased = false
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func holdFirstSnapshot() async {
        guard didHoldFirstSnapshot == false else { return }
        didHoldFirstSnapshot = true
        let waiters = waiters
        self.waiters.removeAll()
        waiters.forEach { $0.resume() }
        guard isReleased == false else { return }
        await withCheckedContinuation { continuation in
            precondition(releaseContinuation == nil, "Only the first Transit snapshot can wait")
            releaseContinuation = continuation
        }
    }

    func waitUntilHeld() async {
        guard didHoldFirstSnapshot == false else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
