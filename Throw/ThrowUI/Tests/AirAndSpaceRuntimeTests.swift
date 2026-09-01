import Foundation
import Testing
import ThrowCore
@testable import ThrowUI

struct AirAndSpaceRuntimeTests {
    @Test func validEmptyPollMakesFreshActivationReady() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: date,
            observations: [],
            decodingDiagnostics: .none,
        )
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: FixedAircraftSourceFactory(snapshot: snapshot),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = AirAndSpaceRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            routeResolver: FlightRouteResolver(source: EmptyFlightRouteSource()),
            routeLogger: DiscardingFlightRouteLogger(),
            dateProvider: FixtureDateProvider(date: date),
        )
        var updates = await runtime.stateUpdates().makeAsyncIterator()
        _ = await updates.next()
        let observer = try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            altitude: Altitude(feet: 0),
        )
        let query = try AircraftQuery(
            observer: observer,
            center: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            includeGroundAircraft: false,
        )

        await runtime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: .adaptive,
            lease: lease(42),
        )

        var ready: AirAndSpaceRuntimeUpdate?
        while let update = await updates.next() {
            if update.successfulActivationLease == lease(42) {
                ready = update
                break
            }
        }
        let update = try #require(ready)
        #expect(update.health == .healthy(lastUpdate: date, visibleContentCount: 0))
        #expect(update.layerFrame?.marks.isEmpty == true)
        #expect(update.experienceFrame.experienceID == .airAndSpace)
        #expect(update.activePollingSignature != nil)

        await runtime.deactivate(lease: lease(42), reporting: .idle)
    }

    @Test func laterActivationSupersedesActivationSuspendedDuringReset() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let flightsRuntime = ControllableFlightsLayerRuntime(suspendedResetNumbers: [1])
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ConfigurationEchoAircraftSourceFactory(date: date),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: flightsRuntime,
            date: date,
        )
        let query = try query()
        let replacementConfiguration = try localReadsbConfiguration()

        let supersededActivation = Task {
            await runtime.activate(
                configuration: .adsbLol,
                query: query,
                labelMode: .adaptive,
                lease: lease(1),
            )
        }
        await flightsRuntime.waitForResetCount(1)

        await runtime.activate(
            configuration: replacementConfiguration,
            query: query,
            labelMode: .adaptive,
            lease: lease(2),
        )
        await flightsRuntime.releaseReset(1)
        await supersededActivation.value

        let pollingState = await coordinator.currentState()
        #expect(pollingState.sourceKind == .readsb)

        await runtime.deactivate(lease: lease(2), reporting: .idle)
    }

    @Test func visibleCountRejectsAnOlderActivationGeneration() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: date,
            observations: [],
            decodingDiagnostics: .none,
        )
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: FixedAircraftSourceFactory(snapshot: snapshot),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            date: date,
        )
        _ = await runtime.stateUpdates()

        try await runtime.activate(
            configuration: .adsbLol,
            query: query(),
            labelMode: .adaptive,
            lease: lease(42),
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == lease(42)
        }

        await runtime.updateVisibleContentCount(7, lease: lease(41))
        #expect(
            await runtime.currentUpdate().health ==
                .healthy(lastUpdate: date, visibleContentCount: 0),
        )

        await runtime.updateVisibleContentCount(7, lease: lease(42))
        #expect(
            await runtime.currentUpdate().health ==
                .healthy(lastUpdate: date, visibleContentCount: 7),
        )

        await runtime.deactivate(lease: lease(42), reporting: .idle)
    }

    @Test func laterActivationSupersedesDeactivationSuspendedDuringReset() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let flightsRuntime = ControllableFlightsLayerRuntime(suspendedResetNumbers: [2])
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ConfigurationEchoAircraftSourceFactory(date: date),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: flightsRuntime,
            date: date,
        )
        let query = try query()
        let replacementConfiguration = try localReadsbConfiguration()
        _ = await runtime.stateUpdates()

        await runtime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: .adaptive,
            lease: lease(1),
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == lease(1)
        }

        let supersededDeactivation = Task {
            await runtime.deactivate(lease: lease(1), reporting: .idle)
        }
        await flightsRuntime.waitForResetCount(2)

        await runtime.activate(
            configuration: replacementConfiguration,
            query: query,
            labelMode: .adaptive,
            lease: lease(2),
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == lease(2)
        }
        await flightsRuntime.releaseReset(2)
        await supersededDeactivation.value

        let update = await runtime.currentUpdate()
        #expect(update.health == .healthy(lastUpdate: date, visibleContentCount: 0))
        #expect(update.snapshot?.source == .readsb)
        #expect(update.activePollingSignature?.configuration.kind == .readsb)

        await runtime.deactivate(lease: lease(2), reporting: .idle)
    }

    @Test func staleLeaseQueuedBeforeReplacementCannotDeactivateTheReplacement() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ConfigurationEchoAircraftSourceFactory(date: date),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: LayerCatalog.standard.flights.runtimeFactory(),
            date: date,
        )
        let oldLease = lease(1)
        let replacementLease = lease(2)
        let query = try query()
        _ = await runtime.stateUpdates()

        await runtime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: .adaptive,
            lease: oldLease,
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == oldLease
        }

        let gate = ManualDeactivationGate()
        let staleDeactivation = Task {
            await gate.wait()
            await runtime.deactivate(lease: oldLease, reporting: .idle)
        }
        await gate.waitUntilBlocked()

        try await runtime.activate(
            configuration: localReadsbConfiguration(),
            query: query,
            labelMode: .adaptive,
            lease: replacementLease,
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == replacementLease
        }
        await gate.release()
        await staleDeactivation.value

        let update = await runtime.currentUpdate()
        #expect(update.activationLease == replacementLease)
        #expect(update.successfulActivationLease == replacementLease)
        #expect(update.activePollingSignature?.configuration.kind == .readsb)
        #expect(await coordinator.currentState().sourceKind == .readsb)

        await runtime.deactivate(lease: replacementLease, reporting: .idle)
    }

    private func makeRuntime(
        pollingCoordinator: AircraftPollingCoordinator,
        flightsRuntime: any FlightsLayerRunning,
        date: Date,
    ) -> AirAndSpaceRuntime {
        AirAndSpaceRuntime(
            pollingCoordinator: pollingCoordinator,
            flightsRuntime: flightsRuntime,
            routeResolver: FlightRouteResolver(source: EmptyFlightRouteSource()),
            routeLogger: DiscardingFlightRouteLogger(),
            dateProvider: FixtureDateProvider(date: date),
        )
    }

    private func query() throws -> AircraftQuery {
        let observer = try ObserverPosition(
            coordinate: GeoCoordinate(latitude: 37, longitude: -122),
            altitude: Altitude(feet: 0),
        )
        return try AircraftQuery(
            observer: observer,
            center: observer.coordinate,
            viewport: .map(MapViewport(radius: NauticalMiles(value: 50))),
            includeGroundAircraft: false,
        )
    }

    private func localReadsbConfiguration() throws -> AircraftSourceConfiguration {
        let url = try #require(URL(string: "http://receiver.local/data/aircraft.json"))
        return try .readsb(ReadsbConfiguration(aircraftJSONURL: url))
    }

    private func lease(_ generation: UInt64) -> ProjectionActivationLease {
        ProjectionActivationLease(
            experienceID: .airAndSpace,
            generation: .init(rawValue: generation),
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await condition() == false {
            guard clock.now < deadline else {
                throw AirAndSpaceRuntimeTestError.conditionTimedOut
            }
            await Task.yield()
        }
    }
}

private enum AirAndSpaceRuntimeTestError: Error {
    case conditionTimedOut
}

private actor ManualDeactivationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            precondition(self.continuation == nil, "Only one deactivation can wait at the gate")
            self.continuation = continuation
            let waiters = blockedWaiters
            blockedWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
    }

    func waitUntilBlocked() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        continuation?.resume()
        continuation = nil
    }
}

extension AircraftPollingState {
    fileprivate var sourceKind: AircraftSourceKind? {
        switch self {
            case let .loading(source): source
            case let .healthy(snapshot, _): snapshot.source
            case let .retrying(lastGoodSnapshot, _, _, _): lastGoodSnapshot?.source
            case .idle, .failed, .quiet: nil
        }
    }
}

private actor ControllableFlightsLayerRuntime: FlightsLayerRunning {
    private let suspendedResetNumbers: Set<Int>
    private var resetCount = 0
    private var resetContinuations: [Int: CheckedContinuation<Void, Never>] = [:]
    private var resetCountWaiters: [Int: [CheckedContinuation<Void, Never>]] = [:]

    init(suspendedResetNumbers: Set<Int>) {
        self.suspendedResetNumbers = suspendedResetNumbers
    }

    func frame(
        for input: FlightsLayerInput,
    ) async throws -> ProjectionLayerFrame<FlightsLayerKind> {
        ProjectionLayerFrame(observedAt: input.snapshot.fetchedAt, marks: [])
    }

    func reset() async {
        resetCount += 1
        let resetNumber = resetCount
        resumeResetCountWaiters()
        guard suspendedResetNumbers.contains(resetNumber) else { return }
        await withCheckedContinuation { continuation in
            resetContinuations[resetNumber] = continuation
        }
    }

    func waitForResetCount(_ expectedCount: Int) async {
        guard resetCount < expectedCount else { return }
        await withCheckedContinuation { continuation in
            resetCountWaiters[expectedCount, default: []].append(continuation)
        }
    }

    func releaseReset(_ resetNumber: Int) {
        resetContinuations.removeValue(forKey: resetNumber)?.resume()
    }

    private func resumeResetCountWaiters() {
        let completedCounts = resetCountWaiters.keys.filter { $0 <= resetCount }
        for completedCount in completedCounts {
            let continuations = resetCountWaiters.removeValue(forKey: completedCount) ?? []
            continuations.forEach { $0.resume() }
        }
    }
}

private struct ConfigurationEchoAircraftSourceFactory: AircraftSourceProducing {
    let date: Date

    func makeSource(
        configuration: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource {
        ConfiguredAircraftSource(
            source: ConfigurationEchoAircraftSource(kind: configuration.kind, date: date),
            baseCadence: .seconds(300),
            metadataWarning: nil,
        )
    }
}

private struct ConfigurationEchoAircraftSource: AircraftObservationSource {
    let kind: AircraftSourceKind
    let date: Date

    func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
        AircraftSnapshot(
            source: kind,
            fetchedAt: date,
            observations: [],
            decodingDiagnostics: .none,
        )
    }
}

private struct FixedAircraftSourceFactory: AircraftSourceProducing {
    let snapshot: AircraftSnapshot

    func makeSource(
        configuration _: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource {
        ConfiguredAircraftSource(
            source: FixedAircraftSource(snapshot: snapshot),
            baseCadence: .seconds(300),
            metadataWarning: nil,
        )
    }
}

private struct FixedAircraftSource: AircraftObservationSource {
    let snapshot: AircraftSnapshot

    func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
        snapshot
    }
}

private struct LongAircraftPollingClock: AircraftPollingClock {
    let date: Date

    init(now: Date) {
        date = now
    }

    func now() async -> Date {
        date
    }

    func sleep(for _: Duration) async throws {
        try await Task.sleep(for: .seconds(3600))
    }
}

private struct EmptyFlightRouteSource: FlightRouteSource {
    func routes(
        for _: [FlightRouteQuery],
    ) async throws -> [FlightCallsign: FlightRoute] {
        [:]
    }
}
