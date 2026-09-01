import Foundation
import Testing
@_spi(Testing) import ThrowCore
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
            sessionFailureLogger: DiscardingThrowSessionFailureLogger(),
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

        _ = await runtime.activate(
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
        #expect(update.flightsFrame?.marks.isEmpty == true)
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

        _ = await runtime.activate(
            configuration: replacementConfiguration,
            query: query,
            labelMode: .adaptive,
            lease: lease(2),
        )
        await flightsRuntime.releaseReset(1)
        _ = await supersededActivation.value

        let pollingUpdate = await coordinator.currentUpdate()
        #expect(pollingUpdate.sourceKind == .readsb)

        await runtime.deactivate(lease: lease(2), reporting: .idle)
    }

    @Test func oldPollCannotSatisfyActivationSuspendedDuringReset() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let snapshotGate = ControlledSnapshotGate()
        let flightsRuntime = ControllableFlightsLayerRuntime(suspendedResetNumbers: [2])
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: SuspendedOldSnapshotFactory(gate: snapshotGate, date: date),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: flightsRuntime,
            date: date,
        )
        let query = try query()
        let oldLease = lease(1)
        let replacementLease = lease(2)
        _ = await runtime.stateUpdates()

        _ = await runtime.activate(
            configuration: .adsbLol,
            query: query,
            labelMode: .adaptive,
            lease: oldLease,
        )
        await snapshotGate.waitUntilBlocked()

        let replacement = Task {
            try await runtime.activate(
                configuration: localReadsbConfiguration(),
                query: query,
                labelMode: .adaptive,
                lease: replacementLease,
            )
        }
        await flightsRuntime.waitForResetCount(2)

        await snapshotGate.release()
        try await waitUntil {
            if case let .active(publication) = await coordinator.currentUpdate(),
               case let .healthy(snapshot, _) = publication.state
            {
                snapshot.source == .adsbLol
            } else {
                false
            }
        }
        let oldUpdate = await coordinator.currentUpdate()
        try await waitUntil {
            await runtime.lastObservedPollingUpdateForTesting() == oldUpdate
        }

        let suspended = await runtime.currentUpdate()
        #expect(suspended.activationLease == replacementLease)
        #expect(suspended.successfulActivationLease == nil)
        #expect(suspended.snapshot == nil)
        #expect(suspended.activePollingSignature == nil)
        #expect(suspended.health == .loading)

        await flightsRuntime.releaseReset(2)
        _ = try await replacement.value
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == replacementLease
        }
        let ready = await runtime.currentUpdate()
        #expect(ready.snapshot?.source == .readsb)
        #expect(ready.activePollingSignature?.configuration.kind == .readsb)

        await runtime.deactivate(lease: replacementLease, reporting: .idle)
    }

    @Test func currentUpdateRecoveryCannotRegressANewerStreamPublication() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let snapshotGate = ControlledSnapshotGate()
        let currentUpdateGate = CurrentUpdateReturnGate()
        let flightsRuntime = ControllableFrameFlightsLayerRuntime()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: SuspendedOldSnapshotFactory(gate: snapshotGate, date: date),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        await coordinator.setBeforeReturningCurrentUpdateForTesting { update in
            await currentUpdateGate.hold(update)
        }
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: flightsRuntime,
            date: date,
        )
        let activationLease = lease(1)
        _ = await runtime.stateUpdates()

        let activation = Task {
            try await runtime.activate(
                configuration: .adsbLol,
                query: query(),
                labelMode: .adaptive,
                lease: activationLease,
            )
        }
        let capturedUpdate = await currentUpdateGate.waitUntilBlocked()
        let capturedPublication = try #require(capturedUpdate.activePublication)
        #expect(capturedPublication.state == .loading(source: .adsbLol))

        await snapshotGate.release()
        await flightsRuntime.waitUntilFrameBlocked()
        let streamedPublication = try #require(
            await runtime.lastObservedPollingUpdateForTesting()?.activePublication,
        )
        #expect(streamedPublication.revision > capturedPublication.revision)

        await currentUpdateGate.release()
        try await activation.value
        await coordinator.setBeforeReturningCurrentUpdateForTesting(nil)
        await flightsRuntime.releaseFrame()

        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        let ready = await runtime.currentUpdate()
        #expect(ready.health == .healthy(lastUpdate: date, visibleContentCount: 0))
        #expect(ready.snapshot?.source == .adsbLol)
        #expect(ready.flightsFrame != nil)

        await runtime.deactivate(lease: activationLease, reporting: .idle)
    }

    @Test func newerDeactivationTombstonesActivationSuspendedDuringReset() async throws {
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

        let supersededActivation = Task {
            await runtime.activate(
                configuration: .adsbLol,
                query: query,
                labelMode: .adaptive,
                lease: lease(1),
            )
        }
        await flightsRuntime.waitForResetCount(1)

        await runtime.deactivate(lease: lease(2), reporting: .idle)
        await flightsRuntime.releaseReset(1)
        _ = await supersededActivation.value

        let update = await runtime.currentUpdate()
        #expect(update.activationLease == nil)
        #expect(update.activePollingSignature == nil)
        #expect(update.health == .idle)
        #expect(await coordinator.currentUpdate() == .inactive)
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

        _ = try await runtime.activate(
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

        _ = await runtime.activate(
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

        _ = await runtime.activate(
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

        _ = await runtime.activate(
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

        _ = try await runtime.activate(
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
        #expect(await coordinator.currentUpdate().sourceKind == .readsb)

        await runtime.deactivate(lease: replacementLease, reporting: .idle)
    }

    @Test func failedSemanticRebuildPreservesTheLastGoodPresentation() async throws {
        let date = Date(timeIntervalSince1970: 1_800_100_000)
        let snapshot = AircraftSnapshot(
            source: .adsbLol,
            fetchedAt: date,
            observations: [],
            decodingDiagnostics: .none,
        )
        let flightsRuntime = FailingSecondFrameFlightsLayerRuntime()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: FixedAircraftSourceFactory(snapshot: snapshot),
            clock: LongAircraftPollingClock(now: date),
            logger: DiscardingAircraftPollingLogger(),
        )
        let runtime = makeRuntime(
            pollingCoordinator: coordinator,
            flightsRuntime: flightsRuntime,
            date: date,
        )
        let activationLease = lease(42)
        _ = await runtime.stateUpdates()

        _ = try await runtime.activate(
            configuration: .adsbLol,
            query: query(),
            labelMode: .adaptive,
            lease: activationLease,
        )
        try await waitUntil {
            await runtime.currentUpdate().successfulActivationLease == activationLease
        }
        let lastGood = await runtime.currentUpdate()

        await runtime.refreshPresentation(labelMode: .callsigns)

        let failed = await runtime.currentUpdate()
        #expect(failed.semanticPreparationState == .failed)
        #expect(failed.health == .failed(.decoding))
        #expect(failed.snapshot == lastGood.snapshot)
        #expect(failed.flightsFrame == lastGood.flightsFrame)
        #expect(failed.successfulActivationLease == activationLease)

        await runtime.deactivate(lease: activationLease, reporting: .idle)
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
            sessionFailureLogger: DiscardingThrowSessionFailureLogger(),
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

extension AircraftPollingUpdate {
    fileprivate var activePublication: AircraftPollingActiveUpdate? {
        guard case let .active(publication) = self else { return nil }
        return publication
    }

    fileprivate var sourceKind: AircraftSourceKind? {
        switch self {
            case .inactive: nil
            case let .active(publication):
                switch publication.state {
                    case let .loading(source): source
                    case let .healthy(snapshot, _): snapshot.source
                    case let .retrying(lastGoodSnapshot, _, _, _): lastGoodSnapshot?.source
                    case .failed, .quiet: nil
                }
        }
    }
}

private actor CurrentUpdateReturnGate {
    private var capturedUpdate: AircraftPollingUpdate?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<AircraftPollingUpdate, Never>] = []

    func hold(_ update: AircraftPollingUpdate) async {
        precondition(releaseContinuation == nil, "Only one current update can wait at the gate")
        capturedUpdate = update
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume(returning: update) }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilBlocked() async -> AircraftPollingUpdate {
        if let capturedUpdate { return capturedUpdate }
        return await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private actor ControllableFrameFlightsLayerRuntime: FlightsLayerRunning {
    private var frameContinuation: CheckedContinuation<Void, Never>?
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func frame(
        for input: FlightsLayerInput,
    ) async -> ProjectionLayerFrame<FlightsLayerKind> {
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            frameContinuation = continuation
        }
        return ProjectionLayerFrame(observedAt: input.snapshot.fetchedAt, marks: [])
    }

    func reset() {}

    func waitUntilFrameBlocked() async {
        guard frameContinuation == nil else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func releaseFrame() {
        frameContinuation?.resume()
        frameContinuation = nil
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

private actor ControlledSnapshotGate {
    private var isReleased = false
    private var releaseContinuations: [CheckedContinuation<Void, Never>] = []
    private var blockedWaiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard isReleased == false else { return }
        let waiters = blockedWaiters
        blockedWaiters.removeAll()
        waiters.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuations.append(continuation)
        }
    }

    func waitUntilBlocked() async {
        guard releaseContinuations.isEmpty else { return }
        await withCheckedContinuation { continuation in
            blockedWaiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let continuations = releaseContinuations
        releaseContinuations.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private enum FailingSecondFrameError: Error {
    case frame
}

private actor FailingSecondFrameFlightsLayerRuntime: FlightsLayerRunning {
    private var frameCallCount = 0

    func frame(
        for input: FlightsLayerInput,
    ) throws -> ProjectionLayerFrame<FlightsLayerKind> {
        frameCallCount += 1
        guard frameCallCount == 1 else {
            throw FailingSecondFrameError.frame
        }
        return ProjectionLayerFrame(observedAt: input.snapshot.fetchedAt, marks: [])
    }

    func reset() {}
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

private struct SuspendedOldSnapshotFactory: AircraftSourceProducing {
    let gate: ControlledSnapshotGate
    let date: Date

    func makeSource(
        configuration: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource {
        let source: any AircraftObservationSource = if configuration.kind == .adsbLol {
            ControlledSnapshotSource(gate: gate, kind: configuration.kind, date: date)
        } else {
            ConfigurationEchoAircraftSource(kind: configuration.kind, date: date)
        }
        return ConfiguredAircraftSource(
            source: source,
            baseCadence: .seconds(300),
            metadataWarning: nil,
        )
    }
}

private struct ControlledSnapshotSource: AircraftObservationSource {
    let gate: ControlledSnapshotGate
    let kind: AircraftSourceKind
    let date: Date

    func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
        await gate.wait()
        return AircraftSnapshot(
            source: kind,
            fetchedAt: date,
            observations: [],
            decodingDiagnostics: .none,
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

    func sleep(for _: Duration) async throws(CancellationError) {
        do {
            try await Task.sleep(for: .seconds(3600))
        } catch {
            throw CancellationError()
        }
    }
}

private struct EmptyFlightRouteSource: FlightRouteSource {
    func routes(
        for _: [FlightRouteQuery],
    ) async throws -> [FlightCallsign: FlightRoute] {
        [:]
    }
}
