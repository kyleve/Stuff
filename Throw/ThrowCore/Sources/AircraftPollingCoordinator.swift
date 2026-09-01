import Foundation

public protocol AircraftPollingClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws(CancellationError)
}

public struct SystemAircraftPollingClock: AircraftPollingClock {
    public init() {}

    public func now() async -> Date {
        Date()
    }

    public func sleep(for duration: Duration) async throws(CancellationError) {
        do {
            try await Task.sleep(for: duration)
        } catch {
            // Task.sleep uses its error channel only for task cancellation.
            throw CancellationError()
        }
    }
}

/// A capability that identifies one accepted physical polling activation.
///
/// Only ``AircraftPollingCoordinator`` can mint production values. Consumers
/// use the token to reject updates from a superseded polling task.
public struct AircraftPollingActivationToken: Hashable, Sendable {
    fileprivate let rawValue: UInt64

    fileprivate init(mintedRawValue: UInt64) {
        rawValue = mintedRawValue
    }

    #if DEBUG
        @_spi(Testing) public init(testingRawValue: UInt64) {
            rawValue = testingRawValue
        }
    #endif
}

/// The semantic state of an active physical poller.
public enum AircraftPollingState: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case loading(source: AircraftSourceKind)
    case healthy(snapshot: AircraftSnapshot, nextPollAt: Date)
    case retrying(
        lastGoodSnapshot: AircraftSnapshot?,
        failure: AircraftSourceFailure,
        failureStartedAt: Date,
        nextRetryAt: Date,
    )
    case failed(AircraftSourceFailure)
    case quiet

    public var snapshot: AircraftSnapshot? {
        switch self {
            case let .healthy(snapshot, _): snapshot
            case let .retrying(lastGoodSnapshot, _, _, _): lastGoodSnapshot
            case .loading, .failed, .quiet: nil
        }
    }

    public var description: String {
        "<AircraftPollingState redacted>"
    }

    public var debugDescription: String {
        description
    }
}

/// One ordered semantic publication from an accepted physical poller.
public struct AircraftPollingActiveUpdate: Equatable, Sendable {
    /// A monotonic position in one polling activation's publication stream.
    public struct Revision: Hashable, Comparable, Sendable {
        fileprivate let rawValue: UInt64

        fileprivate init(rawValue: UInt64) {
            self.rawValue = rawValue
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    public let token: AircraftPollingActivationToken
    public let revision: Revision
    public let state: AircraftPollingState

    fileprivate init(
        token: AircraftPollingActivationToken,
        revision: Revision,
        state: AircraftPollingState,
    ) {
        self.token = token
        self.revision = revision
        self.state = state
    }
}

/// A closed polling publication. Active state carries one coordinator-built
/// envelope whose revision is ordered within its activation token.
public enum AircraftPollingUpdate: Equatable, Sendable {
    case inactive
    case active(AircraftPollingActiveUpdate)
}

public enum AircraftPollingBackoff {
    public static func delay(
        baseCadence: Duration,
        failureCount: Int,
        retryAfterSeconds: Double?,
    ) -> Duration {
        precondition(failureCount > 0)
        let baseSeconds = baseCadence.secondsValue
        let exponent = min(failureCount - 1, 20)
        let exponential = baseSeconds * pow(2, Double(exponent))
        let bounded = min(max(exponential, 2), 60)
        let retryAfter = max(0, retryAfterSeconds ?? 0)
        return .seconds(max(retryAfter, bounded))
    }
}

/// Owns the one structured polling task. Replacements cancel and drain before
/// a new generation starts, so late provider responses cannot mix frames.
public actor AircraftPollingCoordinator {
    private struct ActivePolling {
        let token: AircraftPollingActivationToken
        let configuration: AircraftSourceConfiguration
        let query: AircraftQuery
    }

    private let sourceFactory: any AircraftSourceProducing
    private let clock: any AircraftPollingClock
    private let logger: any AircraftPollingLogging
    private let updatesStream: AsyncStream<AircraftPollingUpdate>
    private let continuation: AsyncStream<AircraftPollingUpdate>.Continuation

    private var pollTask: Task<Void, Never>?
    private var lifecycleTail: Task<Void, Never>?
    private var lifecycleRequestGeneration: UInt64 = 0
    private var generation: UInt64 = 0
    private var activePolling: ActivePolling?
    private var activePublicationRevision: UInt64 = 0
    private var update = AircraftPollingUpdate.inactive
    #if DEBUG
        private var beforeReturningCurrentUpdateForTesting:
            (@Sendable (AircraftPollingUpdate) async -> Void)?
    #endif

    public init(
        sourceFactory: any AircraftSourceProducing,
        clock: any AircraftPollingClock,
        logger: any AircraftPollingLogging,
    ) {
        self.sourceFactory = sourceFactory
        self.clock = clock
        self.logger = logger
        let pair = AsyncStream.makeStream(
            of: AircraftPollingUpdate.self,
            bufferingPolicy: .bufferingNewest(1),
        )
        updatesStream = pair.stream
        continuation = pair.continuation
    }

    deinit {
        pollTask?.cancel()
        lifecycleTail?.cancel()
        continuation.finish()
    }

    public func stateUpdates() -> AsyncStream<AircraftPollingUpdate> {
        continuation.yield(update)
        return updatesStream
    }

    public func currentUpdate() async -> AircraftPollingUpdate {
        let currentUpdate = update
        #if DEBUG
            await beforeReturningCurrentUpdateForTesting?(currentUpdate)
        #endif
        return currentUpdate
    }

    #if DEBUG
        @_spi(Testing) public func lifecycleRequestGenerationForTesting() -> UInt64 {
            lifecycleRequestGeneration
        }

        @_spi(Testing) public func setBeforeReturningCurrentUpdateForTesting(
            _ operation: (@Sendable (AircraftPollingUpdate) async -> Void)?,
        ) {
            beforeReturningCurrentUpdateForTesting = operation
        }
    #endif

    public func activate(
        configuration: AircraftSourceConfiguration,
        query: AircraftQuery,
        quiet: Bool,
    ) async -> AircraftPollingActivationToken? {
        lifecycleRequestGeneration &+= 1
        let requestGeneration = lifecycleRequestGeneration
        let token = AircraftPollingActivationToken(mintedRawValue: requestGeneration)
        let predecessor = lifecycleTail
        let operation = Task(name: "Throw activate aircraft source") { [weak self] in
            await predecessor?.value
            guard Task.isCancelled == false, let self,
                  await isCurrentLifecycleRequest(requestGeneration)
            else { return }
            await replace(
                configuration: configuration,
                query: query,
                quiet: quiet,
                token: token,
                lifecycleRequestGeneration: requestGeneration,
            )
        }
        lifecycleTail = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
            Task(name: "Settle cancelled Throw source activation") { [weak self] in
                await self?.scheduleCancellationCleanup(for: requestGeneration)
            }
        }
        guard Task.isCancelled == false,
              isCurrentLifecycleRequest(requestGeneration),
              activePolling?.token == token
        else { return nil }
        return token
    }

    public func update(
        query: AircraftQuery,
        quiet: Bool,
    ) async -> AircraftPollingActivationToken? {
        lifecycleRequestGeneration &+= 1
        let requestGeneration = lifecycleRequestGeneration
        let token = AircraftPollingActivationToken(mintedRawValue: requestGeneration)
        let predecessor = lifecycleTail
        let operation = Task(name: "Throw update aircraft query") { [weak self] in
            await predecessor?.value
            guard Task.isCancelled == false, let self,
                  await isCurrentLifecycleRequest(requestGeneration)
            else { return }
            await performUpdate(
                query: query,
                quiet: quiet,
                token: token,
                lifecycleRequestGeneration: requestGeneration,
            )
        }
        lifecycleTail = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
            Task(name: "Settle cancelled Throw query update") { [weak self] in
                await self?.scheduleCancellationCleanup(for: requestGeneration)
            }
        }
        guard Task.isCancelled == false,
              isCurrentLifecycleRequest(requestGeneration),
              activePolling?.token == token
        else { return nil }
        return token
    }

    public func deactivate() async {
        lifecycleRequestGeneration &+= 1
        let requestGeneration = lifecycleRequestGeneration
        let predecessor = lifecycleTail
        let operation = Task(name: "Throw deactivate aircraft source") { [weak self] in
            await predecessor?.value
            guard Task.isCancelled == false, let self,
                  await isCurrentLifecycleRequest(requestGeneration)
            else { return }
            await performDeactivate(lifecycleRequestGeneration: requestGeneration)
        }
        lifecycleTail = operation
        await withTaskCancellationHandler {
            await operation.value
        } onCancel: {
            operation.cancel()
            Task(name: "Settle cancelled Throw deactivation") { [weak self] in
                await self?.scheduleCancellationCleanup(for: requestGeneration)
            }
        }
    }

    private func scheduleCancellationCleanup(for requestGeneration: UInt64) {
        guard isCurrentLifecycleRequest(requestGeneration) else { return }
        lifecycleRequestGeneration &+= 1
        let cleanupGeneration = lifecycleRequestGeneration
        let predecessor = lifecycleTail
        let cleanup = Task(name: "Throw cancelled lifecycle cleanup") { [weak self] in
            await predecessor?.value
            guard let self,
                  await isCurrentLifecycleRequest(cleanupGeneration)
            else { return }
            await performDeactivate(lifecycleRequestGeneration: cleanupGeneration)
        }
        lifecycleTail = cleanup
    }

    private func performUpdate(
        query: AircraftQuery,
        quiet: Bool,
        token: AircraftPollingActivationToken,
        lifecycleRequestGeneration: UInt64,
    ) async {
        guard let activePolling else {
            publish(.inactive)
            return
        }
        await replace(
            configuration: activePolling.configuration,
            query: query,
            quiet: quiet,
            token: token,
            lifecycleRequestGeneration: lifecycleRequestGeneration,
        )
    }

    private func performDeactivate(lifecycleRequestGeneration: UInt64) async {
        generation &+= 1
        activePolling = nil
        activePublicationRevision = 0
        publish(.inactive)
        let oldTask = pollTask
        pollTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard Task.isCancelled == false,
              isCurrentLifecycleRequest(lifecycleRequestGeneration)
        else { return }
        publish(.inactive)
    }

    private func replace(
        configuration: AircraftSourceConfiguration,
        query: AircraftQuery,
        quiet: Bool,
        token: AircraftPollingActivationToken,
        lifecycleRequestGeneration: UInt64,
    ) async {
        generation &+= 1
        let replacementGeneration = generation
        activePolling = nil
        activePublicationRevision = 0
        publish(.inactive)
        let oldTask = pollTask
        pollTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard Task.isCancelled == false,
              generation == replacementGeneration,
              isCurrentLifecycleRequest(lifecycleRequestGeneration)
        else {
            if isCurrentLifecycleRequest(lifecycleRequestGeneration) {
                activePolling = nil
                publish(.inactive)
            }
            return
        }

        activePolling = ActivePolling(
            token: token,
            configuration: configuration,
            query: query,
        )
        activePublicationRevision = 0
        guard quiet == false else {
            publish(.quiet, token: token)
            return
        }
        publish(.loading(source: configuration.kind), token: token)
        pollTask = Task(name: "Throw aircraft polling") { [weak self] in
            await self?.run(
                configuration: configuration,
                query: query,
                token: token,
                generation: replacementGeneration,
            )
        }
    }

    private func isCurrentLifecycleRequest(_ requestGeneration: UInt64) -> Bool {
        lifecycleRequestGeneration == requestGeneration
    }

    private func run(
        configuration: AircraftSourceConfiguration,
        query: AircraftQuery,
        token: AircraftPollingActivationToken,
        generation runGeneration: UInt64,
    ) async {
        var requestCount = 0
        var lastGood: AircraftSnapshot?
        defer {
            logger.record(
                AircraftPollingLogEvent.pollingStopped(
                    AircraftPollingLogEvent.PollingStop(
                        source: configuration.kind,
                        requestCount: requestCount,
                        decodedAircraftCount: lastGood?.observations.count,
                    ),
                ),
            )
        }

        let factoryStartedAt = await clock.now()
        let configuredSource: ConfiguredAircraftSource
        do {
            configuredSource = try await sourceFactory.makeSource(configuration: configuration)
        } catch is CancellationError {
            return
        } catch let failure as AircraftSourceFailure {
            let completedAt = await clock.now()
            guard generation == runGeneration, Task.isCancelled == false else { return }
            recordFactoryFailure(
                failure,
                configuration: configuration,
                startedAt: factoryStartedAt,
                completedAt: completedAt,
            )
            publish(.failed(failure), token: token)
            return
        } catch {
            let completedAt = await clock.now()
            guard generation == runGeneration, Task.isCancelled == false else { return }
            let failure = AircraftSourceFailure.invalidConfiguration
            recordFactoryFailure(
                failure,
                configuration: configuration,
                startedAt: factoryStartedAt,
                completedAt: completedAt,
            )
            publish(.failed(failure), token: token)
            return
        }
        guard generation == runGeneration, Task.isCancelled == false else { return }

        var failureCount = 0
        var failureStartedAt: Date?
        logger.record(
            AircraftPollingLogEvent.sourceActivated(
                AircraftPollingLogEvent.SourceActivation(source: configuration.kind),
            ),
        )
        if let metadataWarning = configuredSource.metadataWarning {
            logger.record(
                AircraftPollingLogEvent.receiverMetadataFallback(
                    AircraftPollingLogEvent.ReceiverMetadataFallback(
                        failureCategory: Self.category(metadataWarning),
                    ),
                ),
            )
        }

        while Task.isCancelled == false {
            requestCount += 1
            let requestStartedAt = await clock.now()
            do {
                let snapshot = try await configuredSource.source.snapshot(for: query)
                try Task.checkCancellation()
                guard generation == runGeneration else { return }
                let completedAt = await clock.now()
                guard generation == runGeneration else { return }
                failureCount = 0
                failureStartedAt = nil
                lastGood = snapshot
                let nextPollAt = completedAt.addingTimeInterval(
                    configuredSource.baseCadence.secondsValue,
                )
                publish(
                    .healthy(snapshot: snapshot, nextPollAt: nextPollAt),
                    token: token,
                )
                logger.record(
                    AircraftPollingLogEvent.requestSucceeded(
                        AircraftPollingLogEvent.RequestSuccess(
                            source: configuration.kind,
                            requestCount: requestCount,
                            durationMilliseconds: max(
                                0,
                                Int(completedAt.timeIntervalSince(requestStartedAt) * 1000),
                            ),
                            httpStatus: snapshot.successfulHTTPStatus,
                            decodedAircraftCount: snapshot.observations.count,
                        ),
                    ),
                )
                if let discardedRecords = snapshot.decodingDiagnostics.discardedRecords {
                    logger.record(
                        AircraftPollingLogEvent.partialSchemaDrift(
                            AircraftPollingLogEvent.PartialSchemaDrift(
                                source: configuration.kind,
                                requestCount: requestCount,
                                httpStatus: snapshot.successfulHTTPStatus,
                                decodedAircraftCount: snapshot.observations.count,
                                discardedRecords: discardedRecords,
                            ),
                        ),
                    )
                }
                try await clock.sleep(for: configuredSource.baseCadence)
            } catch is CancellationError {
                return
            } catch let failure as AircraftSourceFailure {
                guard generation == runGeneration else { return }
                failureCount += 1
                let completedAt = await clock.now()
                guard generation == runGeneration else { return }
                let startedAt = failureStartedAt ?? completedAt
                failureStartedAt = startedAt
                logger.record(
                    AircraftPollingLogEvent.requestFailed(
                        AircraftPollingLogEvent.RequestFailure(
                            source: configuration.kind,
                            requestCount: requestCount,
                            durationMilliseconds: max(
                                0,
                                Int(completedAt.timeIntervalSince(requestStartedAt) * 1000),
                            ),
                            httpStatus: Self.statusCode(failure),
                            failureCategory: Self.category(failure),
                        ),
                    ),
                )
                guard failure.isRetryable else {
                    publish(.failed(failure), token: token)
                    return
                }
                let delay = AircraftPollingBackoff.delay(
                    baseCadence: configuredSource.baseCadence,
                    failureCount: failureCount,
                    retryAfterSeconds: failure.retryAfterSeconds,
                )
                let retryAt = completedAt.addingTimeInterval(delay.secondsValue)
                publish(
                    .retrying(
                        lastGoodSnapshot: lastGood,
                        failure: failure,
                        failureStartedAt: startedAt,
                        nextRetryAt: retryAt,
                    ),
                    token: token,
                )
                logger.record(
                    AircraftPollingLogEvent.retryScheduled(
                        AircraftPollingLogEvent.RetrySchedule(
                            source: configuration.kind,
                            requestCount: requestCount,
                            httpStatus: Self.statusCode(failure),
                            decodedAircraftCount: lastGood?.observations.count,
                            backoffSeconds: delay.secondsValue,
                            failureCategory: Self.category(failure),
                        ),
                    ),
                )
                do {
                    try await clock.sleep(for: delay)
                } catch {
                    return
                }
            } catch {
                guard generation == runGeneration else { return }
                failureCount += 1
                let completedAt = await clock.now()
                guard generation == runGeneration else { return }
                let startedAt = failureStartedAt ?? completedAt
                failureStartedAt = startedAt
                let failure = AircraftSourceFailure.transport(.other)
                logger.record(
                    AircraftPollingLogEvent.requestFailed(
                        AircraftPollingLogEvent.RequestFailure(
                            source: configuration.kind,
                            requestCount: requestCount,
                            durationMilliseconds: max(
                                0,
                                Int(completedAt.timeIntervalSince(requestStartedAt) * 1000),
                            ),
                            httpStatus: Self.statusCode(failure),
                            failureCategory: Self.category(failure),
                        ),
                    ),
                )
                let delay = AircraftPollingBackoff.delay(
                    baseCadence: configuredSource.baseCadence,
                    failureCount: failureCount,
                    retryAfterSeconds: nil,
                )
                publish(
                    .retrying(
                        lastGoodSnapshot: lastGood,
                        failure: failure,
                        failureStartedAt: startedAt,
                        nextRetryAt: completedAt.addingTimeInterval(delay.secondsValue),
                    ),
                    token: token,
                )
                logger.record(
                    AircraftPollingLogEvent.retryScheduled(
                        AircraftPollingLogEvent.RetrySchedule(
                            source: configuration.kind,
                            requestCount: requestCount,
                            httpStatus: Self.statusCode(failure),
                            decodedAircraftCount: lastGood?.observations.count,
                            backoffSeconds: delay.secondsValue,
                            failureCategory: Self.category(failure),
                        ),
                    ),
                )
                do {
                    try await clock.sleep(for: delay)
                } catch {
                    return
                }
            }
        }
    }

    private func publish(
        _ state: AircraftPollingState,
        token: AircraftPollingActivationToken,
    ) {
        guard activePolling?.token == token else { return }
        if case let .active(currentUpdate) = update,
           currentUpdate.token == token,
           currentUpdate.state == state
        {
            return
        }
        precondition(
            activePublicationRevision < UInt64.max,
            "Aircraft polling publication revision overflow",
        )
        activePublicationRevision += 1
        publish(.active(AircraftPollingActiveUpdate(
            token: token,
            revision: .init(rawValue: activePublicationRevision),
            state: state,
        )))
    }

    private func publish(_ newUpdate: AircraftPollingUpdate) {
        guard update != newUpdate else { return }
        update = newUpdate
        continuation.yield(newUpdate)
    }

    private func recordFactoryFailure(
        _ failure: AircraftSourceFailure,
        configuration: AircraftSourceConfiguration,
        startedAt: Date,
        completedAt: Date,
    ) {
        logger.record(
            AircraftPollingLogEvent.requestFailed(
                AircraftPollingLogEvent.RequestFailure(
                    source: configuration.kind,
                    requestCount: 0,
                    durationMilliseconds: max(
                        0,
                        Int(completedAt.timeIntervalSince(startedAt) * 1000),
                    ),
                    httpStatus: Self.statusCode(failure),
                    failureCategory: Self.category(failure),
                ),
            ),
        )
    }

    private static func statusCode(_ failure: AircraftSourceFailure) -> Int? {
        switch failure {
            case .invalidCredential: 401
            case .subscriptionRequired: 402
            case .entitlementRejected: 403
            case .quotaReached: 429
            case let .provider(statusCode, _): statusCode
            case .invalidConfiguration, .missingCredential, .transport, .decoding: nil
        }
    }

    private static func category(
        _ failure: AircraftSourceFailure,
    ) -> AircraftPollingLogEvent.FailureCategory {
        switch failure {
            case .invalidConfiguration: .invalidConfiguration
            case .missingCredential: .missingCredential
            case .invalidCredential: .invalidCredential
            case .subscriptionRequired: .subscriptionRequired
            case .entitlementRejected: .entitlementRejected
            case .quotaReached: .quotaReached
            case .provider: .provider
            case let .transport(category):
                switch category {
                    case .cancelled: .transportCancelled
                    case .timedOut: .transportTimedOut
                    case .offline: .transportOffline
                    case .localNetworkDenied: .transportLocalNetworkDenied
                    case .connection: .transportConnection
                    case .invalidResponse: .transportInvalidResponse
                    case .other: .transportOther
                }
            case .decoding: .decoding
        }
    }
}

extension Duration {
    fileprivate var secondsValue: Double {
        let components = components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }
}
