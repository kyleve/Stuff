import Foundation
import Synchronization
import Testing
@_spi(Testing) @testable import ThrowCore

struct AircraftPollingCoordinatorTests {
    @Test func stateStreamBuffersOnlyLatestTransition() async throws {
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: UnusedFactory(),
            clock: FixedPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        let stream = await coordinator.stateUpdates()
        let query = try ThrowCoreFixture.mapQuery()
        await coordinator.activate(configuration: .adsbLol, query: query, quiet: true)
        await coordinator.deactivate()
        await coordinator.activate(configuration: .adsbLol, query: query, quiet: true)

        var iterator = stream.makeAsyncIterator()
        #expect(await iterator.next() == .quiet)
        await coordinator.deactivate()
    }

    @Test(arguments: [
        (1, 10.0),
        (2, 20.0),
        (4, 60.0),
        (10, 60.0),
    ])
    func exponentialBackoffCapsAtSixtySeconds(failureCount: Int, expected: Double) {
        let delay = AircraftPollingBackoff.delay(
            baseCadence: .seconds(10),
            failureCount: failureCount,
            retryAfterSeconds: nil,
        )
        #expect(delay == .seconds(expected))
    }

    @Test func serverRetryAfterCanExceedSixtySecondCap() {
        let delay = AircraftPollingBackoff.delay(
            baseCadence: .seconds(10),
            failureCount: 1,
            retryAfterSeconds: 180,
        )
        #expect(delay == .seconds(180))
    }

    @Test func configurationFailureBecomesRedStateWithoutFallback() async throws {
        let logger = RecordingPollingLogger()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: FailingFactory(failure: .missingCredential),
            clock: FixedPollingClock(),
            logger: logger,
        )
        let stream = await coordinator.stateUpdates()
        try await coordinator.activate(
            configuration: .adsbExchangeRapidAPI(
                ADSBExchangeConfiguration(
                    pollingInterval: PollingInterval(seconds: 10),
                ),
            ),
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )

        var iterator = stream.makeAsyncIterator()
        var failedState: AircraftPollingState?
        while let state = await iterator.next() {
            if case .failed = state {
                failedState = state
                break
            }
        }
        #expect(failedState == .failed(.missingCredential))
        try await waitUntil {
            logger.events().contains { $0.kind == .pollingStopped }
        }
        let events = logger.events()
        let failure = try #require(events.first { $0.kind == .requestFailed })
        #expect(failure.requestCount == 0)
        #expect(failure.failureCategory == .missingCredential)
        let stopped = try #require(events.first { $0.kind == .pollingStopped })
        #expect(stopped.requestCount == 0)
        await coordinator.deactivate()
    }

    @Test func successfulRequestLogsActualHTTPStatusAndPollingStop() async throws {
        let logger = RecordingPollingLogger()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: SuccessfulStatusFactory(statusCode: 206),
            clock: SuspendingPollingClock(),
            logger: logger,
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        try await waitUntil {
            logger.events().contains { $0.kind == .requestSucceeded }
        }

        let succeeded = try #require(logger.events().first { $0.kind == .requestSucceeded })
        #expect(succeeded.httpStatus == 206)
        await coordinator.deactivate()
        try await waitUntil {
            logger.events().contains { $0.kind == .pollingStopped }
        }
        let stopped = try #require(logger.events().last { $0.kind == .pollingStopped })
        #expect(stopped.requestCount == 1)
    }

    @Test func partialSchemaDriftLogsPrivacySafeCountsAtWarningLevel() async throws {
        let diagnostics = AircraftSnapshotDecodingDiagnostics(
            malformedRecordCount: 2,
            missingPositionRecordCount: 3,
        )
        let logger = RecordingPollingLogger()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: DiagnosticSnapshotFactory(diagnostics: diagnostics),
            clock: SuspendingPollingClock(),
            logger: logger,
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        try await waitUntil {
            logger.events().contains { $0.kind == .partialSchemaDrift }
        }

        let event = try #require(logger.events().first { $0.kind == .partialSchemaDrift })
        #expect(event.level == .warning)
        #expect(event.decodedAircraftCount == 0)
        #expect(event.decodingDiagnostics == diagnostics)
        let fields = event.remoteFields
        #expect(fields.map(\.key.rawValue) == [
            "kind",
            "source",
            "malformed_record_count",
            "missing_position_record_count",
        ])
        guard case let .category(kind) = fields[0].value,
              case let .category(source) = fields[1].value,
              case let .count(malformedCount) = fields[2].value,
              case let .count(missingPositionCount) = fields[3].value
        else {
            Issue.record("Expected closed categories and record counts.")
            await coordinator.deactivate()
            return
        }
        #expect(kind.rawValue == "partial-schema-drift")
        #expect(source.rawValue == "adsb-lol")
        #expect(malformedCount == 2)
        #expect(missingPositionCount == 3)
        await coordinator.deactivate()
    }

    @Test func readsbMetadataFallbackLogsASeparateWarningFromActivation() async throws {
        let logger = RecordingPollingLogger()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ReadsbMetadataFallbackFactory(),
            clock: SuspendingPollingClock(),
            logger: logger,
        )
        try await coordinator.activate(
            configuration: localReadsbConfiguration(),
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        try await waitUntil {
            logger.events().contains { $0.kind == .receiverMetadataFallback }
        }

        let events = logger.events()
        let activated = try #require(events.first { $0.kind == .sourceActivated })
        let fallback = try #require(events.first { $0.kind == .receiverMetadataFallback })
        #expect(activated.level == .info)
        #expect(activated.failureCategory == nil)
        #expect(fallback.level == .warning)
        #expect(fallback.source == .readsb)
        #expect(fallback.failureCategory == .transportOffline)
        #expect(fallback.remoteFields.map(\.key.rawValue) == [
            "kind",
            "source",
            "failure_category",
        ])
        await coordinator.deactivate()
    }

    @Test func localNetworkDenialLogsDistinctRedactedFailureCategory() async throws {
        let logger = RecordingPollingLogger()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: FailingFactory(failure: .transport(.localNetworkDenied)),
            clock: FixedPollingClock(),
            logger: logger,
        )
        try await coordinator.activate(
            configuration: localReadsbConfiguration(),
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )

        try await waitUntil {
            logger.events().contains { $0.kind == .requestFailed }
        }
        let failure = try #require(logger.events().first { $0.kind == .requestFailed })
        #expect(failure.source == .readsb)
        #expect(failure.failureCategory == .transportLocalNetworkDenied)
        #expect(failure.httpStatus == nil)
        #expect(failure.remoteFields.isEmpty)
        await coordinator.deactivate()
    }

    @Test func genericRequestFailureLogsRedactedFailureAndRetryEvents() async throws {
        let errorSentinel = "generic-error-do-not-leak"
        let logger = RecordingPollingLogger()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: GenericFailingFactory(errorSentinel: errorSentinel),
            clock: SuspendingPollingClock(),
            logger: logger,
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        try await waitUntil {
            logger.events().contains { $0.kind == .retryScheduled }
        }

        let events = logger.events()
        let requestFailed = try #require(events.first { $0.kind == .requestFailed })
        let retryScheduled = try #require(events.first { $0.kind == .retryScheduled })
        #expect(requestFailed.failureCategory == .transportOther)
        #expect(requestFailed.httpStatus == nil)
        #expect(retryScheduled.failureCategory == .transportOther)
        #expect(retryScheduled.backoffSeconds == 10)
        for event in [requestFailed, retryScheduled] {
            #expect(event.message.contains(errorSentinel) == false)
            #expect(event.remoteMessage.contains(errorSentinel) == false)
            #expect(String(describing: event).contains(errorSentinel) == false)
            #expect(String(reflecting: event).contains(errorSentinel) == false)
        }
        await coordinator.deactivate()
    }

    @Test func retryStatePreservesLastGoodObservationsUntilPresentationFadesThem() async throws {
        let source = FutureThenFailingSource()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: SingleSourceFactory(source: source),
            clock: SingleImmediateSleepPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        try await waitUntil {
            if case .retrying = await coordinator.currentState() {
                true
            } else {
                false
            }
        }

        guard case let .retrying(lastGoodSnapshot, failure, _, _) =
            await coordinator.currentState()
        else {
            Issue.record("Expected retrying state")
            return
        }
        #expect(lastGoodSnapshot?.observations.count == 1)
        #expect(failure == .transport(.offline))
        await coordinator.deactivate()
    }

    @Test func repeatedFailuresDoNotRestartTheVisibilityGracePeriod() async throws {
        let recorder = PollingStateRecorder()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: SingleSourceFactory(source: SuccessfulThenFailingSource()),
            clock: RetryObservationPollingClock(recorder: recorder),
            logger: DiscardingAircraftPollingLogger(),
        )
        let stream = await coordinator.stateUpdates()
        let recordingTask = Task(name: "Record retry visibility dates") {
            for await state in stream {
                guard Task.isCancelled == false else { return }
                await recorder.record(state)
            }
        }
        defer { recordingTask.cancel() }

        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        try await waitUntil {
            await recorder.retryFailureDates().count >= 2
        }

        let dates = await recorder.retryFailureDates()
        #expect(dates[0] == dates[1])
        await coordinator.deactivate()
    }

    @Test func replacementCancelsAndDrainsBeforeStartingTheNewSource() async throws {
        let journal = PollingEventJournal()
        let gate = BlockingSnapshotGate()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ProbeSourceFactory(journal: journal, gate: gate),
            clock: SuspendingPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        let stream = await coordinator.stateUpdates()
        let stateRecorder = PollingStateRecorder()
        let stateTask = Task(name: "Record Throw polling states") {
            for await state in stream {
                guard Task.isCancelled == false else { return }
                await stateRecorder.record(state)
            }
        }

        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        await journal.wait(for: .snapshotStarted(.adsbLol))

        let readsbConfiguration = try localReadsbConfiguration()
        let query = try ThrowCoreFixture.mapQuery()
        let replacement = Task(name: "Replace Throw polling source") {
            await coordinator.activate(
                configuration: readsbConfiguration,
                query: query,
                quiet: false,
            )
        }
        await journal.wait(for: .cancellationObserved(.adsbLol))
        #expect(await journal.contains(.factoryCreated(.readsb)) == false)

        await gate.release()
        await replacement.value
        await journal.wait(for: .snapshotStarted(.readsb))
        try await waitUntil {
            if case let .healthy(snapshot, _) = await coordinator.currentState() {
                snapshot.source == .readsb
            } else {
                false
            }
        }
        try await waitUntil {
            await stateRecorder.states().contains { state in
                if case let .healthy(snapshot, _) = state {
                    snapshot.source == .readsb
                } else {
                    false
                }
            }
        }

        stateTask.cancel()
        await stateTask.value
        let recordedStates = await stateRecorder.states()
        let healthySources = recordedStates.compactMap { state in
            if case let .healthy(snapshot, _) = state { snapshot.source } else { nil }
        }
        #expect(healthySources == [.readsb])
        let events = await journal.events()
        let cancellationIndex = try #require(events.firstIndex(of: .cancellationObserved(.adsbLol)))
        let replacementFactoryIndex = try #require(events.firstIndex(of: .factoryCreated(.readsb)))
        #expect(cancellationIndex < replacementFactoryIndex)
        await coordinator.deactivate()
    }

    @Test func queuedDeactivationSupersedesPaidActivationBeforeItCanRequest() async throws {
        let journal = PollingEventJournal()
        let gate = BlockingSnapshotGate()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ProbeSourceFactory(journal: journal, gate: gate),
            clock: SuspendingPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        await journal.wait(for: .snapshotStarted(.adsbLol))

        let configuration = try paidConfiguration()
        let query = try ThrowCoreFixture.mapQuery()
        let paidActivation = Task(name: "Queue paid Throw source") {
            await coordinator.activate(
                configuration: configuration,
                query: query,
                quiet: false,
            )
        }
        await journal.wait(for: .cancellationObserved(.adsbLol))
        let generationBeforeStop = await coordinator.lifecycleRequestGenerationForTesting()
        let stop = Task(name: "Stop queued Throw source") {
            await coordinator.deactivate()
        }
        try await waitUntil {
            await coordinator.lifecycleRequestGenerationForTesting() > generationBeforeStop
        }

        await gate.release()
        await paidActivation.value
        await stop.value

        #expect(await journal.contains(.factoryCreated(.adsbExchangeRapidAPI)) == false)
        #expect(await coordinator.currentState() == .idle)
    }

    @Test func cancellingAReplacementCallerCannotStartItsPaidSource() async throws {
        let journal = PollingEventJournal()
        let gate = BlockingSnapshotGate()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ProbeSourceFactory(journal: journal, gate: gate),
            clock: SuspendingPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        await journal.wait(for: .snapshotStarted(.adsbLol))

        let configuration = try paidConfiguration()
        let query = try ThrowCoreFixture.mapQuery()
        let paidActivation = Task(name: "Cancel paid Throw source") {
            await coordinator.activate(
                configuration: configuration,
                query: query,
                quiet: false,
            )
        }
        await journal.wait(for: .cancellationObserved(.adsbLol))
        paidActivation.cancel()
        await gate.release()
        await paidActivation.value

        #expect(await journal.contains(.factoryCreated(.adsbExchangeRapidAPI)) == false)
        try await waitUntil {
            await coordinator.currentState() == .idle
        }
    }

    @Test func cancellingDeactivationWhileItDrainsStillSettlesIdle() async throws {
        let journal = PollingEventJournal()
        let gate = BlockingSnapshotGate()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ProbeSourceFactory(journal: journal, gate: gate),
            clock: SuspendingPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        await journal.wait(for: .snapshotStarted(.adsbLol))

        let stop = Task(name: "Cancel Throw deactivation while draining") {
            await coordinator.deactivate()
        }
        await journal.wait(for: .cancellationObserved(.adsbLol))
        stop.cancel()
        await gate.release()
        await stop.value

        try await waitUntil {
            await coordinator.currentState() == .idle
        }
    }

    @Test func cancelledStopAfterStaleReplacementStillSettlesIdle() async throws {
        let journal = PollingEventJournal()
        let gate = BlockingSnapshotGate()
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: ProbeSourceFactory(journal: journal, gate: gate),
            clock: SuspendingPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        try await coordinator.activate(
            configuration: .adsbLol,
            query: ThrowCoreFixture.mapQuery(),
            quiet: false,
        )
        await journal.wait(for: .snapshotStarted(.adsbLol))

        let configuration = try paidConfiguration()
        let query = try ThrowCoreFixture.mapQuery()
        let replacement = Task(name: "Queue paid Throw replacement") {
            await coordinator.activate(
                configuration: configuration,
                query: query,
                quiet: false,
            )
        }
        await journal.wait(for: .cancellationObserved(.adsbLol))

        let generationBeforeStop = await coordinator.lifecycleRequestGenerationForTesting()
        let stop = Task(name: "Cancel superseding Throw stop") {
            await coordinator.deactivate()
        }
        try await waitUntil {
            await coordinator.lifecycleRequestGenerationForTesting() > generationBeforeStop
        }
        stop.cancel()
        await gate.release()
        await replacement.value
        await stop.value

        try await waitUntil {
            await coordinator.currentState() == .idle
        }
        #expect(await journal.contains(.factoryCreated(.adsbExchangeRapidAPI)) == false)
    }

    private func localReadsbConfiguration() throws -> AircraftSourceConfiguration {
        let url = try #require(URL(string: "http://receiver.local/data/aircraft.json"))
        return try .readsb(ReadsbConfiguration(aircraftJSONURL: url))
    }

    private func paidConfiguration() throws -> AircraftSourceConfiguration {
        try .adsbExchangeRapidAPI(
            ADSBExchangeConfiguration(
                pollingInterval: PollingInterval(seconds: 10),
            ),
        )
    }

    private func waitUntil(
        _ condition: @escaping @Sendable () async -> Bool,
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while await condition() == false {
            guard clock.now < deadline else {
                throw PollingTestError.conditionTimedOut
            }
            await Task.yield()
        }
    }

    private struct FixedPollingClock: AircraftPollingClock {
        func now() async -> Date {
            ThrowCoreFixture.date
        }

        func sleep(for _: Duration) async throws {
            try Task.checkCancellation()
        }
    }

    private struct UnusedFactory: AircraftSourceProducing {
        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            throw AircraftSourceFailure.invalidConfiguration
        }
    }

    private struct FailingFactory: AircraftSourceProducing {
        let failure: AircraftSourceFailure

        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            throw failure
        }
    }

    private struct SuccessfulStatusFactory: AircraftSourceProducing {
        let statusCode: Int

        func makeSource(
            configuration: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            ConfiguredAircraftSource(
                source: SuccessfulStatusSource(
                    kind: configuration.kind,
                    statusCode: statusCode,
                ),
                baseCadence: .seconds(300),
                metadataWarning: nil,
            )
        }
    }

    private struct SuccessfulStatusSource: AircraftObservationSource {
        let kind: AircraftSourceKind
        let statusCode: Int

        func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
            AircraftSnapshot(
                source: kind,
                fetchedAt: ThrowCoreFixture.date,
                observations: [],
                successfulHTTPStatus: statusCode,
            )
        }
    }

    private struct DiagnosticSnapshotFactory: AircraftSourceProducing {
        let diagnostics: AircraftSnapshotDecodingDiagnostics

        func makeSource(
            configuration: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            ConfiguredAircraftSource(
                source: DiagnosticSnapshotSource(
                    kind: configuration.kind,
                    diagnostics: diagnostics,
                ),
                baseCadence: .seconds(300),
                metadataWarning: nil,
            )
        }
    }

    private struct DiagnosticSnapshotSource: AircraftObservationSource {
        let kind: AircraftSourceKind
        let diagnostics: AircraftSnapshotDecodingDiagnostics

        func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
            AircraftSnapshot(
                source: kind,
                fetchedAt: ThrowCoreFixture.date,
                observations: [],
                successfulHTTPStatus: 200,
                decodingDiagnostics: diagnostics,
            )
        }
    }

    private struct ReadsbMetadataFallbackFactory: AircraftSourceProducing {
        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            ConfiguredAircraftSource(
                source: SuccessfulStatusSource(kind: .readsb, statusCode: 200),
                baseCadence: .seconds(1),
                metadataWarning: .transport(.offline),
            )
        }
    }

    private struct SingleSourceFactory<Source: AircraftObservationSource>: AircraftSourceProducing {
        let source: Source

        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            ConfiguredAircraftSource(
                source: source,
                baseCadence: .seconds(10),
                metadataWarning: nil,
            )
        }
    }

    private actor FutureThenFailingSource: AircraftObservationSource {
        private var requestCount = 0

        func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
            requestCount += 1
            guard requestCount == 1 else {
                throw AircraftSourceFailure.transport(.offline)
            }
            return try AircraftSnapshot(
                source: .adsbLol,
                fetchedAt: ThrowCoreFixture.date,
                observations: [ThrowCoreFixture.observation(positionAge: -1)],
            )
        }
    }

    private actor SuccessfulThenFailingSource: AircraftObservationSource {
        private var requestCount = 0

        func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
            requestCount += 1
            guard requestCount == 1 else {
                throw AircraftSourceFailure.transport(.offline)
            }
            return try AircraftSnapshot(
                source: .adsbLol,
                fetchedAt: ThrowCoreFixture.date,
                observations: [ThrowCoreFixture.observation()],
            )
        }
    }

    private struct GenericFailingFactory: AircraftSourceProducing {
        let errorSentinel: String

        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            ConfiguredAircraftSource(
                source: GenericFailingSource(errorSentinel: errorSentinel),
                baseCadence: .seconds(10),
                metadataWarning: nil,
            )
        }
    }

    private struct GenericFailingSource: AircraftObservationSource {
        let errorSentinel: String

        func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
            throw SensitiveGenericError(value: errorSentinel)
        }
    }

    private struct SensitiveGenericError: Error {
        let value: String
    }

    private enum PollingTestError: Error {
        case conditionTimedOut
    }
}

private final class RecordingPollingLogger: AircraftPollingLogging {
    private let recordedEvents = Mutex<[AircraftPollingLogEvent]>([])

    func record(_ event: AircraftPollingLogEvent) {
        recordedEvents.withLock { events in
            events.append(event)
        }
    }

    func events() -> [AircraftPollingLogEvent] {
        recordedEvents.withLock { $0 }
    }
}

private enum PollingProbeEvent: Hashable {
    case factoryCreated(AircraftSourceKind)
    case snapshotStarted(AircraftSourceKind)
    case cancellationObserved(AircraftSourceKind)
}

private actor PollingEventJournal {
    private var recordedEvents: [PollingProbeEvent] = []
    private var waiters: [PollingProbeEvent: [CheckedContinuation<Void, Never>]] = [:]

    func record(_ event: PollingProbeEvent) {
        recordedEvents.append(event)
        let continuations = waiters.removeValue(forKey: event) ?? []
        continuations.forEach { $0.resume() }
    }

    func wait(for event: PollingProbeEvent) async {
        if recordedEvents.contains(event) { return }
        await withCheckedContinuation { continuation in
            waiters[event, default: []].append(continuation)
        }
    }

    func contains(_ event: PollingProbeEvent) -> Bool {
        recordedEvents.contains(event)
    }

    func events() -> [PollingProbeEvent] {
        recordedEvents
    }
}

private actor BlockingSnapshotGate {
    private var isReleased = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isReleased { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func release() {
        isReleased = true
        let continuations = waiters
        waiters.removeAll()
        continuations.forEach { $0.resume() }
    }
}

private struct ProbeSourceFactory: AircraftSourceProducing {
    let journal: PollingEventJournal
    let gate: BlockingSnapshotGate

    func makeSource(
        configuration: AircraftSourceConfiguration,
    ) async throws -> ConfiguredAircraftSource {
        await journal.record(.factoryCreated(configuration.kind))
        let source: any AircraftObservationSource = if configuration.kind == .adsbLol {
            CancellationResistantProbeSource(kind: configuration.kind, journal: journal, gate: gate)
        } else {
            ImmediateProbeSource(kind: configuration.kind, journal: journal)
        }
        return ConfiguredAircraftSource(
            source: source,
            baseCadence: .seconds(300),
            metadataWarning: nil,
        )
    }
}

private struct CancellationResistantProbeSource: AircraftObservationSource {
    let kind: AircraftSourceKind
    let journal: PollingEventJournal
    let gate: BlockingSnapshotGate

    func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
        await journal.record(.snapshotStarted(kind))
        return await withTaskCancellationHandler {
            await gate.wait()
            return AircraftSnapshot(
                source: kind,
                fetchedAt: ThrowCoreFixture.date,
                observations: [],
            )
        } onCancel: {
            Task(name: "Record ignored Throw source cancellation") {
                await journal.record(.cancellationObserved(kind))
            }
        }
    }
}

private struct ImmediateProbeSource: AircraftObservationSource {
    let kind: AircraftSourceKind
    let journal: PollingEventJournal

    func snapshot(for _: AircraftQuery) async throws -> AircraftSnapshot {
        await journal.record(.snapshotStarted(kind))
        return AircraftSnapshot(
            source: kind,
            fetchedAt: ThrowCoreFixture.date,
            observations: [],
        )
    }
}

private struct SuspendingPollingClock: AircraftPollingClock {
    func now() async -> Date {
        ThrowCoreFixture.date
    }

    func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

private actor SingleImmediateSleepPollingClock: AircraftPollingClock {
    private var sleepCount = 0

    func now() async -> Date {
        ThrowCoreFixture.date
    }

    func sleep(for duration: Duration) async throws {
        sleepCount += 1
        guard sleepCount > 1 else { return }
        try await Task.sleep(for: duration)
    }
}

private actor RetryObservationPollingClock: AircraftPollingClock {
    private let recorder: PollingStateRecorder
    private var dateOffset: TimeInterval = 0
    private var sleepCount = 0

    init(recorder: PollingStateRecorder) {
        self.recorder = recorder
    }

    func now() async -> Date {
        defer { dateOffset += 1 }
        return ThrowCoreFixture.date.addingTimeInterval(dateOffset)
    }

    func sleep(for duration: Duration) async throws {
        sleepCount += 1
        switch sleepCount {
            case 1:
                return
            case 2:
                // The production stream buffers only its latest state. Hold the
                // first retry until the recorder observes it before permitting
                // the second failure.
                while await recorder.retryFailureDates().isEmpty {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            default:
                try await Task.sleep(for: duration)
        }
    }
}

private actor PollingStateRecorder {
    private var recordedStates: [AircraftPollingState] = []

    func record(_ state: AircraftPollingState) {
        recordedStates.append(state)
    }

    func states() -> [AircraftPollingState] {
        recordedStates
    }

    func retryFailureDates() -> [Date] {
        recordedStates.compactMap { state in
            guard case let .retrying(_, _, failureStartedAt, _) = state else { return nil }
            return failureStartedAt
        }
    }
}
