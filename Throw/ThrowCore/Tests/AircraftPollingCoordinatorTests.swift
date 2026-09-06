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
        _ = await coordinator.activate(configuration: .adsbLol, query: query, quiet: true)
        await coordinator.deactivate()
        let token = try #require(
            await coordinator.activate(configuration: .adsbLol, query: query, quiet: true),
        )

        var iterator = stream.makeAsyncIterator()
        let publication = try #require(await iterator.next()?.activePublication)
        #expect(publication.token == token)
        #expect(publication.state == .quiet)
        await coordinator.deactivate()
    }

    @Test func replacementMintsDistinctTokenAndBindsCurrentUpdate() async throws {
        let coordinator = AircraftPollingCoordinator(
            sourceFactory: UnusedFactory(),
            clock: FixedPollingClock(),
            logger: DiscardingAircraftPollingLogger(),
        )
        let query = try ThrowCoreFixture.mapQuery()
        let first = try #require(
            await coordinator.activate(configuration: .adsbLol, query: query, quiet: true),
        )
        let firstPublication = try #require(
            await coordinator.currentUpdate().activePublication,
        )
        #expect(firstPublication.token == first)
        #expect(firstPublication.state == .quiet)

        let second = try #require(
            await coordinator.activate(configuration: .adsbLol, query: query, quiet: true),
        )
        #expect(second != first)
        let secondPublication = try #require(
            await coordinator.currentUpdate().activePublication,
        )
        #expect(secondPublication.token == second)
        #expect(secondPublication.state == .quiet)
        #expect(secondPublication.revision == firstPublication.revision)

        await coordinator.deactivate()
        #expect(await coordinator.currentUpdate() == .inactive)
    }

    @Test(arguments: [
        (1, 10.0),
        (2, 20.0),
        (4, 60.0),
        (10, 60.0),
    ])
    func exponentialBackoffCapsAtSixtySeconds(
        failureCount: Int,
        expected: Double,
    ) throws {
        let delay = try AircraftPollingBackoff.delay(
            baseCadence: AircraftPollingCadence(duration: .seconds(10)),
            failureCount: failureCount,
            retryAfterSeconds: nil,
        )
        #expect(delay == .seconds(expected))
    }

    @Test func serverRetryAfterCanExceedSixtySecondCap() throws {
        let delay = try AircraftPollingBackoff.delay(
            baseCadence: AircraftPollingCadence(duration: .seconds(10)),
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
        while let update = await iterator.next() {
            if case let .active(publication) = update,
               case .failed = publication.state
            {
                failedState = publication.state
                break
            }
        }
        #expect(failedState == .failed(.missingCredential))
        try await waitUntil {
            logger.events().contains { $0.kind == .pollingStopped }
        }
        let events = logger.events()
        let failure = try #require(events.first { $0.kind == .requestFailed })
        guard case let .requestFailed(failureEvent) = failure else {
            Issue.record("Expected a request failure event.")
            await coordinator.deactivate()
            return
        }
        #expect(failureEvent.requestCount == 0)
        #expect(failureEvent.failureCategory == .missingCredential)
        let stopped = try #require(events.first { $0.kind == .pollingStopped })
        guard case let .pollingStopped(stopEvent) = stopped else {
            Issue.record("Expected a polling stop event.")
            await coordinator.deactivate()
            return
        }
        #expect(stopEvent.requestCount == 0)
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
        guard case let .requestSucceeded(successEvent) = succeeded else {
            Issue.record("Expected a request success event.")
            await coordinator.deactivate()
            return
        }
        #expect(successEvent.httpStatus == 206)
        await coordinator.deactivate()
        try await waitUntil {
            logger.events().contains { $0.kind == .pollingStopped }
        }
        let stopped = try #require(logger.events().last { $0.kind == .pollingStopped })
        guard case let .pollingStopped(stopEvent) = stopped else {
            Issue.record("Expected a polling stop event.")
            await coordinator.deactivate()
            return
        }
        #expect(stopEvent.requestCount == 1)
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
        guard case let .partialSchemaDrift(schemaDrift) = event else {
            Issue.record("Expected a partial schema-drift event.")
            await coordinator.deactivate()
            return
        }
        #expect(event.level == .warning)
        #expect(schemaDrift.decodedAircraftCount == 0)
        #expect(
            schemaDrift.discardedRecords.malformedRecordCount ==
                diagnostics.malformedRecordCount,
        )
        #expect(
            schemaDrift.discardedRecords.missingPositionRecordCount ==
                diagnostics.missingPositionRecordCount,
        )
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
        guard case .sourceActivated = activated else {
            Issue.record("Expected a source activation event.")
            await coordinator.deactivate()
            return
        }
        guard case let .receiverMetadataFallback(fallbackEvent) = fallback else {
            Issue.record("Expected a receiver metadata fallback event.")
            await coordinator.deactivate()
            return
        }
        #expect(activated.level == .info)
        #expect(fallback.level == .warning)
        #expect(fallback.source == .readsb)
        #expect(fallbackEvent.failureCategory == .transportOffline)
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
        guard case let .requestFailed(failureEvent) = failure else {
            Issue.record("Expected a request failure event.")
            await coordinator.deactivate()
            return
        }
        #expect(failureEvent.source == .readsb)
        #expect(failureEvent.failureCategory == .transportLocalNetworkDenied)
        #expect(failureEvent.httpStatus == nil)
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
        guard case let .requestFailed(failureEvent) = requestFailed else {
            Issue.record("Expected a request failure event.")
            await coordinator.deactivate()
            return
        }
        guard case let .retryScheduled(retryEvent) = retryScheduled else {
            Issue.record("Expected a retry schedule event.")
            await coordinator.deactivate()
            return
        }
        #expect(failureEvent.failureCategory == .transportOther)
        #expect(failureEvent.httpStatus == nil)
        #expect(retryEvent.failureCategory == .transportOther)
        #expect(retryEvent.backoffSeconds == 10)
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
            if case let .active(publication) = await coordinator.currentUpdate(),
               case .retrying = publication.state
            {
                true
            } else {
                false
            }
        }

        guard case let .active(publication) = await coordinator.currentUpdate(),
              case let .retrying(lastGoodSnapshot, failure, _, _) = publication.state
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
            for await update in stream {
                guard Task.isCancelled == false else { return }
                await recorder.record(update)
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
            for await update in stream {
                guard Task.isCancelled == false else { return }
                await stateRecorder.record(update)
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
        let replacementToken = try #require(await replacement.value)
        await journal.wait(for: .snapshotStarted(.readsb))
        try await waitUntil {
            if case let .active(publication) = await coordinator.currentUpdate(),
               case let .healthy(snapshot, _) = publication.state
            {
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
        let healthyTokens = await stateRecorder.updates().compactMap { update in
            if case let .active(publication) = update,
               case .healthy = publication.state
            {
                publication.token
            } else {
                nil
            }
        }
        #expect(healthyTokens == [replacementToken])
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
        #expect(await coordinator.currentUpdate() == .inactive)
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
            await coordinator.currentUpdate() == .inactive
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
            await coordinator.currentUpdate() == .inactive
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
            await coordinator.currentUpdate() == .inactive
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

        func sleep(for _: Duration) async throws(CancellationError) {
            if Task.isCancelled {
                throw CancellationError()
            }
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
            try ConfiguredAircraftSource(
                source: SuccessfulStatusSource(
                    kind: configuration.kind,
                    statusCode: statusCode,
                ),
                baseCadence: AircraftPollingCadence(duration: .seconds(300)),
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
                decodingDiagnostics: .none,
            )
        }
    }

    private struct DiagnosticSnapshotFactory: AircraftSourceProducing {
        let diagnostics: AircraftSnapshotDecodingDiagnostics

        func makeSource(
            configuration: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            try ConfiguredAircraftSource(
                source: DiagnosticSnapshotSource(
                    kind: configuration.kind,
                    diagnostics: diagnostics,
                ),
                baseCadence: AircraftPollingCadence(duration: .seconds(300)),
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
            try ConfiguredAircraftSource(
                source: SuccessfulStatusSource(kind: .readsb, statusCode: 200),
                baseCadence: AircraftPollingCadence(duration: .seconds(1)),
                metadataWarning: .transport(.offline),
            )
        }
    }

    private struct SingleSourceFactory<Source: AircraftObservationSource>: AircraftSourceProducing {
        let source: Source

        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            try ConfiguredAircraftSource(
                source: source,
                baseCadence: AircraftPollingCadence(duration: .seconds(10)),
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
                decodingDiagnostics: .none,
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
                decodingDiagnostics: .none,
            )
        }
    }

    private struct GenericFailingFactory: AircraftSourceProducing {
        let errorSentinel: String

        func makeSource(
            configuration _: AircraftSourceConfiguration,
        ) async throws -> ConfiguredAircraftSource {
            try ConfiguredAircraftSource(
                source: GenericFailingSource(errorSentinel: errorSentinel),
                baseCadence: AircraftPollingCadence(duration: .seconds(10)),
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
        return try ConfiguredAircraftSource(
            source: source,
            baseCadence: AircraftPollingCadence(duration: .seconds(300)),
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
                decodingDiagnostics: .none,
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
            decodingDiagnostics: .none,
        )
    }
}

private struct SuspendingPollingClock: AircraftPollingClock {
    func now() async -> Date {
        ThrowCoreFixture.date
    }

    func sleep(for duration: Duration) async throws(CancellationError) {
        try await sleepForPollingTest(for: duration)
    }
}

private actor SingleImmediateSleepPollingClock: AircraftPollingClock {
    private var sleepCount = 0

    func now() async -> Date {
        ThrowCoreFixture.date
    }

    func sleep(for duration: Duration) async throws(CancellationError) {
        sleepCount += 1
        guard sleepCount > 1 else { return }
        try await sleepForPollingTest(for: duration)
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

    func sleep(for duration: Duration) async throws(CancellationError) {
        sleepCount += 1
        switch sleepCount {
            case 1:
                return
            case 2:
                // The production stream buffers only its latest state. Hold the
                // first retry until the recorder observes it before permitting
                // the second failure.
                while await recorder.retryFailureDates().isEmpty {
                    if Task.isCancelled {
                        throw CancellationError()
                    }
                    await Task.yield()
                }
            default:
                try await sleepForPollingTest(for: duration)
        }
    }
}

private func sleepForPollingTest(
    for duration: Duration,
) async throws(CancellationError) {
    do {
        try await Task.sleep(for: duration)
    } catch {
        throw CancellationError()
    }
}

private actor PollingStateRecorder {
    private var recordedUpdates: [AircraftPollingUpdate] = []

    func record(_ update: AircraftPollingUpdate) {
        recordedUpdates.append(update)
    }

    func updates() -> [AircraftPollingUpdate] {
        recordedUpdates
    }

    func states() -> [AircraftPollingState] {
        recordedUpdates.compactMap { update in
            if case let .active(publication) = update { publication.state } else { nil }
        }
    }

    func retryFailureDates() -> [Date] {
        states().compactMap { state in
            guard case let .retrying(_, _, failureStartedAt, _) = state else { return nil }
            return failureStartedAt
        }
    }
}

extension AircraftPollingUpdate {
    fileprivate var activePublication: AircraftPollingActiveUpdate? {
        guard case let .active(publication) = self else { return nil }
        return publication
    }
}
