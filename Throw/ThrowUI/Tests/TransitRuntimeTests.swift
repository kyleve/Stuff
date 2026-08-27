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
        #expect(update.experienceFrame.layers.contains { $0.layerID == .transitNetwork })
        #expect(update.experienceFrame.layers.contains { $0.layerID == .transitVehicles })
        await runtime.deactivate(lease: activationLease, reporting: .idle)
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

    func runtime(source: FixedTransitObservationSource) -> TransitRuntime {
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
