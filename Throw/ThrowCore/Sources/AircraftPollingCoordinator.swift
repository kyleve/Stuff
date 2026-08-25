import Foundation

public protocol AircraftPollingClock: Sendable {
    func now() async -> Date
    func sleep(for duration: Duration) async throws
}

public struct SystemAircraftPollingClock: AircraftPollingClock {
    public init() {}

    public func now() async -> Date {
        Date()
    }

    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

public enum AircraftPollingState: Equatable, Sendable, CustomStringConvertible,
    CustomDebugStringConvertible
{
    case idle
    case loading(source: AircraftSourceKind)
    case healthy(snapshot: AircraftSnapshot, nextPollAt: Date)
    case retrying(
        lastGoodSnapshot: AircraftSnapshot?,
        failure: AircraftSourceFailure,
        nextRetryAt: Date,
    )
    case failed(AircraftSourceFailure)
    case quiet

    public var snapshot: AircraftSnapshot? {
        switch self {
            case let .healthy(snapshot, _): snapshot
            case let .retrying(lastGoodSnapshot, _, _): lastGoodSnapshot
            case .idle, .loading, .failed, .quiet: nil
        }
    }

    public var description: String {
        "<AircraftPollingState redacted>"
    }

    public var debugDescription: String {
        description
    }
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
    private let sourceFactory: any AircraftSourceProducing
    private let clock: any AircraftPollingClock
    private let logger: any AircraftPollingLogging
    private let updatesStream: AsyncStream<AircraftPollingState>
    private let continuation: AsyncStream<AircraftPollingState>.Continuation

    private var pollTask: Task<Void, Never>?
    private var lifecycleTail: Task<Void, Never>?
    private var lifecycleRequestGeneration: UInt64 = 0
    private var generation: UInt64 = 0
    private var activeConfiguration: AircraftSourceConfiguration?
    private var activeQuery: AircraftQuery?
    private var state: AircraftPollingState = .idle

    public init(
        sourceFactory: any AircraftSourceProducing,
        clock: any AircraftPollingClock,
        logger: any AircraftPollingLogging,
    ) {
        self.sourceFactory = sourceFactory
        self.clock = clock
        self.logger = logger
        let pair = AsyncStream.makeStream(
            of: AircraftPollingState.self,
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

    public func stateUpdates() -> AsyncStream<AircraftPollingState> {
        continuation.yield(state)
        return updatesStream
    }

    public func currentState() -> AircraftPollingState {
        state
    }

    #if DEBUG
        @_spi(Testing) public func lifecycleRequestGenerationForTesting() -> UInt64 {
            lifecycleRequestGeneration
        }
    #endif

    public func activate(
        configuration: AircraftSourceConfiguration,
        query: AircraftQuery,
        quiet: Bool,
    ) async {
        lifecycleRequestGeneration &+= 1
        let requestGeneration = lifecycleRequestGeneration
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
    }

    public func update(query: AircraftQuery, quiet: Bool) async {
        lifecycleRequestGeneration &+= 1
        let requestGeneration = lifecycleRequestGeneration
        let predecessor = lifecycleTail
        let operation = Task(name: "Throw update aircraft query") { [weak self] in
            await predecessor?.value
            guard Task.isCancelled == false, let self,
                  await isCurrentLifecycleRequest(requestGeneration)
            else { return }
            await performUpdate(
                query: query,
                quiet: quiet,
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
        lifecycleRequestGeneration: UInt64,
    ) async {
        guard let activeConfiguration else {
            activeQuery = query
            publish(.idle)
            return
        }
        await replace(
            configuration: activeConfiguration,
            query: query,
            quiet: quiet,
            lifecycleRequestGeneration: lifecycleRequestGeneration,
        )
    }

    private func performDeactivate(lifecycleRequestGeneration: UInt64) async {
        generation &+= 1
        activeConfiguration = nil
        activeQuery = nil
        let oldTask = pollTask
        pollTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard Task.isCancelled == false,
              isCurrentLifecycleRequest(lifecycleRequestGeneration)
        else { return }
        publish(.idle)
    }

    private func replace(
        configuration: AircraftSourceConfiguration,
        query: AircraftQuery,
        quiet: Bool,
        lifecycleRequestGeneration: UInt64,
    ) async {
        generation &+= 1
        let replacementGeneration = generation
        let oldTask = pollTask
        pollTask = nil
        oldTask?.cancel()
        await oldTask?.value
        guard Task.isCancelled == false,
              generation == replacementGeneration,
              isCurrentLifecycleRequest(lifecycleRequestGeneration)
        else {
            if isCurrentLifecycleRequest(lifecycleRequestGeneration) {
                activeConfiguration = nil
                activeQuery = nil
                publish(.idle)
            }
            return
        }

        activeConfiguration = configuration
        activeQuery = query
        guard quiet == false else {
            publish(.quiet)
            return
        }
        publish(.loading(source: configuration.kind))
        pollTask = Task(name: "Throw aircraft polling") { [weak self] in
            await self?.run(
                configuration: configuration,
                query: query,
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
        generation runGeneration: UInt64,
    ) async {
        var requestCount = 0
        var lastGood: AircraftSnapshot?
        defer {
            logger.record(
                AircraftPollingLogEvent(
                    kind: .pollingStopped,
                    source: configuration.kind,
                    requestCount: requestCount,
                    durationMilliseconds: nil,
                    httpStatus: nil,
                    decodedAircraftCount: lastGood?.observations.count,
                    backoffSeconds: nil,
                    failureCategory: nil,
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
            publish(.failed(failure))
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
            publish(.failed(failure))
            return
        }
        guard generation == runGeneration, Task.isCancelled == false else { return }

        var failureCount = 0
        logger.record(
            AircraftPollingLogEvent(
                kind: .sourceActivated,
                source: configuration.kind,
                requestCount: requestCount,
                durationMilliseconds: nil,
                httpStatus: nil,
                decodedAircraftCount: nil,
                backoffSeconds: nil,
                failureCategory: configuredSource.metadataWarning.map(Self.category),
            ),
        )

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
                lastGood = snapshot
                let nextPollAt = completedAt.addingTimeInterval(
                    configuredSource.baseCadence.secondsValue,
                )
                publish(.healthy(snapshot: snapshot, nextPollAt: nextPollAt))
                logger.record(
                    AircraftPollingLogEvent(
                        kind: .requestSucceeded,
                        source: configuration.kind,
                        requestCount: requestCount,
                        durationMilliseconds: max(
                            0,
                            Int(completedAt.timeIntervalSince(requestStartedAt) * 1000),
                        ),
                        httpStatus: snapshot.successfulHTTPStatus,
                        decodedAircraftCount: snapshot.observations.count,
                        backoffSeconds: nil,
                        failureCategory: nil,
                    ),
                )
                try await clock.sleep(for: configuredSource.baseCadence)
            } catch is CancellationError {
                return
            } catch let failure as AircraftSourceFailure {
                guard generation == runGeneration else { return }
                failureCount += 1
                let completedAt = await clock.now()
                guard generation == runGeneration else { return }
                logger.record(
                    AircraftPollingLogEvent(
                        kind: .requestFailed,
                        source: configuration.kind,
                        requestCount: requestCount,
                        durationMilliseconds: max(
                            0,
                            Int(completedAt.timeIntervalSince(requestStartedAt) * 1000),
                        ),
                        httpStatus: Self.statusCode(failure),
                        decodedAircraftCount: nil,
                        backoffSeconds: nil,
                        failureCategory: Self.category(failure),
                    ),
                )
                guard failure.isRetryable else {
                    publish(.failed(failure))
                    return
                }
                let delay = AircraftPollingBackoff.delay(
                    baseCadence: configuredSource.baseCadence,
                    failureCount: failureCount,
                    retryAfterSeconds: failure.retryAfterSeconds,
                )
                let freshLastGood = Self.freshSnapshot(lastGood, at: completedAt)
                let retryAt = completedAt.addingTimeInterval(delay.secondsValue)
                publish(
                    .retrying(
                        lastGoodSnapshot: freshLastGood,
                        failure: failure,
                        nextRetryAt: retryAt,
                    ),
                )
                logger.record(
                    AircraftPollingLogEvent(
                        kind: .retryScheduled,
                        source: configuration.kind,
                        requestCount: requestCount,
                        durationMilliseconds: nil,
                        httpStatus: Self.statusCode(failure),
                        decodedAircraftCount: freshLastGood?.observations.count,
                        backoffSeconds: delay.secondsValue,
                        failureCategory: Self.category(failure),
                    ),
                )
                do {
                    try await clock.sleep(for: delay)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            } catch {
                guard generation == runGeneration else { return }
                failureCount += 1
                let completedAt = await clock.now()
                guard generation == runGeneration else { return }
                let failure = AircraftSourceFailure.transport(.other)
                logger.record(
                    AircraftPollingLogEvent(
                        kind: .requestFailed,
                        source: configuration.kind,
                        requestCount: requestCount,
                        durationMilliseconds: max(
                            0,
                            Int(completedAt.timeIntervalSince(requestStartedAt) * 1000),
                        ),
                        httpStatus: Self.statusCode(failure),
                        decodedAircraftCount: nil,
                        backoffSeconds: nil,
                        failureCategory: Self.category(failure),
                    ),
                )
                let delay = AircraftPollingBackoff.delay(
                    baseCadence: configuredSource.baseCadence,
                    failureCount: failureCount,
                    retryAfterSeconds: nil,
                )
                let freshLastGood = Self.freshSnapshot(lastGood, at: completedAt)
                publish(
                    .retrying(
                        lastGoodSnapshot: freshLastGood,
                        failure: failure,
                        nextRetryAt: completedAt.addingTimeInterval(delay.secondsValue),
                    ),
                )
                logger.record(
                    AircraftPollingLogEvent(
                        kind: .retryScheduled,
                        source: configuration.kind,
                        requestCount: requestCount,
                        durationMilliseconds: nil,
                        httpStatus: Self.statusCode(failure),
                        decodedAircraftCount: freshLastGood?.observations.count,
                        backoffSeconds: delay.secondsValue,
                        failureCategory: Self.category(failure),
                    ),
                )
                do {
                    try await clock.sleep(for: delay)
                } catch is CancellationError {
                    return
                } catch {
                    return
                }
            }
        }
    }

    private func publish(_ newState: AircraftPollingState) {
        guard state != newState else { return }
        state = newState
        continuation.yield(newState)
    }

    private static func freshSnapshot(
        _ snapshot: AircraftSnapshot?,
        at date: Date,
    ) -> AircraftSnapshot? {
        guard let snapshot else { return nil }
        let fresh = snapshot.observations.filter {
            guard let age = FlightPredictor.observationAge(
                positionObservedAt: $0.positionObservedAt,
                at: date,
            ) else {
                return false
            }
            return age < FlightPredictor.expirationAge
        }
        guard fresh.isEmpty == false else { return nil }
        return AircraftSnapshot(
            source: snapshot.source,
            fetchedAt: snapshot.fetchedAt,
            observations: fresh,
            successfulHTTPStatus: snapshot.successfulHTTPStatus,
        )
    }

    private func recordFactoryFailure(
        _ failure: AircraftSourceFailure,
        configuration: AircraftSourceConfiguration,
        startedAt: Date,
        completedAt: Date,
    ) {
        logger.record(
            AircraftPollingLogEvent(
                kind: .requestFailed,
                source: configuration.kind,
                requestCount: 0,
                durationMilliseconds: max(
                    0,
                    Int(completedAt.timeIntervalSince(startedAt) * 1000),
                ),
                httpStatus: Self.statusCode(failure),
                decodedAircraftCount: nil,
                backoffSeconds: nil,
                failureCategory: Self.category(failure),
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
