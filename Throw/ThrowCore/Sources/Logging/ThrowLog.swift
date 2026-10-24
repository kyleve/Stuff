import PeriscopeCore

/// Root namespace for Throw's log scope tree.
@LogScope("Throw")
public enum ThrowRootLog {}

/// Semantic process-session outcomes used at Throw's injected logging boundary.
public enum ThrowSessionLogEvent: Equatable, Sendable {
    /// The dependency boundary that prevented Throw from becoming operational.
    public enum ColdLaunchBoundary: String, CaseIterable, Codable, Equatable, Sendable {
        case preferences
        case credential
        case unexpected
    }

    /// A recoverable operation boundary after the session becomes operational.
    public enum PostLaunchOperation: String, CaseIterable, Codable, Equatable, Sendable {
        case preferencePersistence = "preference-persistence"
        case aircraftSource = "aircraft-source"
        case rapidAPICredential = "rapidapi-credential"
        case flightradar24Credential = "flightradar24-credential"
        case location
        case playlist
        case onboarding
        case projectionPreparation = "projection-preparation"
        case projectionRendering = "projection-rendering"
    }

    case durableLoggingReady
    case durableLoggingUnavailable(description: String)
    case durableLoggingHistoryPruned(expiredEventCount: Int, overflowEventCount: Int)
    case durableLoggingHistoryPruneFailed(description: String)
    case coldLaunchFailed(boundary: ColdLaunchBoundary)
    case softwareCreditsLoadFailed
    case postLaunchOperationFailed(operation: PostLaunchOperation)

    public var level: LogLevel {
        switch self {
            case .durableLoggingReady, .durableLoggingHistoryPruned:
                .info
            case .durableLoggingHistoryPruneFailed:
                .warning
            case .durableLoggingUnavailable, .coldLaunchFailed,
                 .softwareCreditsLoadFailed, .postLaunchOperationFailed:
                .error
        }
    }

    public var message: String {
        switch self {
            case .durableLoggingReady:
                "Durable logging is ready"
            case let .durableLoggingUnavailable(description):
                "Durable logging is unavailable: \(description)"
            case let .durableLoggingHistoryPruned(expiredEventCount, overflowEventCount):
                "Pruned \(expiredEventCount) expired log event(s) and \(overflowEventCount) event(s) past the size limit"
            case let .durableLoggingHistoryPruneFailed(description):
                "Failed to prune durable log history: \(description)"
            case let .coldLaunchFailed(boundary):
                "Cold launch failed at the \(boundary.rawValue) boundary"
            case .softwareCreditsLoadFailed:
                "Software credits failed to load"
            case let .postLaunchOperationFailed(operation):
                "Post-launch operation failed at the \(operation.rawValue) boundary"
        }
    }
}

public enum AircraftPollingLogEvent: Hashable, Sendable {
    public enum Kind: String, CaseIterable, Codable, Hashable, Sendable {
        case sourceActivated = "source-activated"
        case receiverMetadataFallback = "receiver-metadata-fallback"
        case requestSucceeded = "request-succeeded"
        case partialSchemaDrift = "partial-schema-drift"
        case requestFailed = "request-failed"
        case retryScheduled = "retry-scheduled"
        case pollingStopped = "polling-stopped"
    }

    public enum FailureCategory: String, CaseIterable, Codable, Hashable, Sendable {
        case invalidConfiguration = "invalid-configuration"
        case missingCredential = "missing-credential"
        case invalidCredential = "invalid-credential"
        case subscriptionRequired = "subscription-required"
        case entitlementRejected = "entitlement-rejected"
        case quotaReached = "quota-reached"
        case provider
        case transportCancelled = "transport-cancelled"
        case transportTimedOut = "transport-timed-out"
        case transportOffline = "transport-offline"
        case transportLocalNetworkDenied = "transport-local-network-denied"
        case transportConnection = "transport-connection"
        case transportInvalidResponse = "transport-invalid-response"
        case transportOther = "transport-other"
        case decoding
    }

    public struct SourceActivation: Hashable, Sendable {
        public let source: AircraftSourceKind

        public init(source: AircraftSourceKind) {
            self.source = source
        }
    }

    public struct ReceiverMetadataFallback: Hashable, Sendable {
        public let failureCategory: FailureCategory

        public init(failureCategory: FailureCategory) {
            self.failureCategory = failureCategory
        }
    }

    public struct RequestSuccess: Hashable, Sendable {
        public let source: AircraftSourceKind
        public let requestCount: Int
        public let durationMilliseconds: Int
        public let httpStatus: Int?
        public let decodedAircraftCount: Int

        public init(
            source: AircraftSourceKind,
            requestCount: Int,
            durationMilliseconds: Int,
            httpStatus: Int?,
            decodedAircraftCount: Int,
        ) {
            self.source = source
            self.requestCount = requestCount
            self.durationMilliseconds = durationMilliseconds
            self.httpStatus = httpStatus
            self.decodedAircraftCount = decodedAircraftCount
        }
    }

    public struct PartialSchemaDrift: Hashable, Sendable {
        public let source: AircraftSourceKind
        public let requestCount: Int
        public let httpStatus: Int?
        public let decodedAircraftCount: Int
        public let discardedRecords: AircraftSnapshotDecodingDiagnostics.DiscardedRecords

        public init(
            source: AircraftSourceKind,
            requestCount: Int,
            httpStatus: Int?,
            decodedAircraftCount: Int,
            discardedRecords: AircraftSnapshotDecodingDiagnostics.DiscardedRecords,
        ) {
            self.source = source
            self.requestCount = requestCount
            self.httpStatus = httpStatus
            self.decodedAircraftCount = decodedAircraftCount
            self.discardedRecords = discardedRecords
        }
    }

    public struct RequestFailure: Hashable, Sendable {
        public let source: AircraftSourceKind
        public let requestCount: Int
        public let durationMilliseconds: Int
        public let httpStatus: Int?
        public let failureCategory: FailureCategory

        public init(
            source: AircraftSourceKind,
            requestCount: Int,
            durationMilliseconds: Int,
            httpStatus: Int?,
            failureCategory: FailureCategory,
        ) {
            self.source = source
            self.requestCount = requestCount
            self.durationMilliseconds = durationMilliseconds
            self.httpStatus = httpStatus
            self.failureCategory = failureCategory
        }
    }

    public struct RetrySchedule: Hashable, Sendable {
        public let source: AircraftSourceKind
        public let requestCount: Int
        public let httpStatus: Int?
        public let decodedAircraftCount: Int?
        public let backoffSeconds: Double
        public let failureCategory: FailureCategory

        public init(
            source: AircraftSourceKind,
            requestCount: Int,
            httpStatus: Int?,
            decodedAircraftCount: Int?,
            backoffSeconds: Double,
            failureCategory: FailureCategory,
        ) {
            self.source = source
            self.requestCount = requestCount
            self.httpStatus = httpStatus
            self.decodedAircraftCount = decodedAircraftCount
            self.backoffSeconds = backoffSeconds
            self.failureCategory = failureCategory
        }
    }

    public struct PollingStop: Hashable, Sendable {
        public let source: AircraftSourceKind
        public let requestCount: Int
        public let decodedAircraftCount: Int?

        public init(
            source: AircraftSourceKind,
            requestCount: Int,
            decodedAircraftCount: Int?,
        ) {
            self.source = source
            self.requestCount = requestCount
            self.decodedAircraftCount = decodedAircraftCount
        }
    }

    case sourceActivated(SourceActivation)
    case receiverMetadataFallback(ReceiverMetadataFallback)
    case requestSucceeded(RequestSuccess)
    case partialSchemaDrift(PartialSchemaDrift)
    case requestFailed(RequestFailure)
    case retryScheduled(RetrySchedule)
    case pollingStopped(PollingStop)

    public var kind: Kind {
        switch self {
            case .sourceActivated: .sourceActivated
            case .receiverMetadataFallback: .receiverMetadataFallback
            case .requestSucceeded: .requestSucceeded
            case .partialSchemaDrift: .partialSchemaDrift
            case .requestFailed: .requestFailed
            case .retryScheduled: .retryScheduled
            case .pollingStopped: .pollingStopped
        }
    }

    public var source: AircraftSourceKind {
        switch self {
            case let .sourceActivated(event): event.source
            case .receiverMetadataFallback: .readsb
            case let .requestSucceeded(event): event.source
            case let .partialSchemaDrift(event): event.source
            case let .requestFailed(event): event.source
            case let .retryScheduled(event): event.source
            case let .pollingStopped(event): event.source
        }
    }

    public var requestCount: Int {
        switch self {
            case .sourceActivated, .receiverMetadataFallback: 0
            case let .requestSucceeded(event): event.requestCount
            case let .partialSchemaDrift(event): event.requestCount
            case let .requestFailed(event): event.requestCount
            case let .retryScheduled(event): event.requestCount
            case let .pollingStopped(event): event.requestCount
        }
    }

    public var level: LogLevel {
        switch self {
            case .sourceActivated, .requestSucceeded, .pollingStopped:
                .info
            case .receiverMetadataFallback, .partialSchemaDrift, .requestFailed,
                 .retryScheduled:
                .warning
        }
    }

    public var message: String {
        "Aircraft polling \(kind.rawValue) for \(source.rawValue)"
    }
}

/// A redacted failure loading Throw's bundled geographic archive.
public struct GeographyLogEvent: Equatable, Sendable {
    public enum FailureCategory: String, CaseIterable, Codable, Hashable, Sendable {
        case resourceMissing = "resource-missing"
        case invalidArchive = "invalid-archive"
        case unexpected
    }

    public let failureCategory: FailureCategory

    public init(failureCategory: FailureCategory) {
        self.failureCategory = failureCategory
    }

    public var level: LogLevel {
        .error
    }

    public var message: String {
        "Bundled geography load failed: \(failureCategory.rawValue)"
    }
}

/// A redacted outcome from optional flight-route enrichment.
public struct FlightRouteLogEvent: Equatable, Sendable {
    public enum Outcome: String, CaseIterable, Codable, Hashable, Sendable {
        case succeeded
        case providerFailed = "provider-failed"
        case transportFailed = "transport-failed"
        case decodingFailed = "decoding-failed"
    }

    public let outcome: Outcome

    public init(outcome: Outcome) {
        self.outcome = outcome
    }

    public var level: LogLevel {
        outcome == .succeeded ? .info : .warning
    }

    public var message: String {
        "Flight route enrichment \(outcome.rawValue)"
    }
}

/// A privacy-safe aggregate sample of the projection motion pipeline.
public struct ProjectionMotionLogEvent: Equatable, Sendable {
    public let framesPerSecond: Double
    public let aircraftCount: Int
    public let usableHorizontalMotionPercent: Double?
    public let positionDerivedMotionPercent: Double?
    public let meanSampleAgeSeconds: Double?
    public let meanProjectedSpeedPerSecond: Double?
    public let meanCorrectionDistance: Double?
    public let previousSnapshotRetainedPercent: Double?

    public init(
        framesPerSecond: Double,
        aircraftCount: Int,
        usableHorizontalMotionPercent: Double?,
        positionDerivedMotionPercent: Double?,
        meanSampleAgeSeconds: Double?,
        meanProjectedSpeedPerSecond: Double?,
        meanCorrectionDistance: Double?,
        previousSnapshotRetainedPercent: Double?,
    ) {
        self.framesPerSecond = framesPerSecond
        self.aircraftCount = aircraftCount
        self.usableHorizontalMotionPercent = usableHorizontalMotionPercent
        self.positionDerivedMotionPercent = positionDerivedMotionPercent
        self.meanSampleAgeSeconds = meanSampleAgeSeconds
        self.meanProjectedSpeedPerSecond = meanProjectedSpeedPerSecond
        self.meanCorrectionDistance = meanCorrectionDistance
        self.previousSnapshotRetainedPercent = previousSnapshotRetainedPercent
    }

    public var level: LogLevel {
        .info
    }

    public var message: String {
        "Projection motion aggregate"
    }
}

@LogScope("ThrowSession")
enum ThrowSessionLog {
    @LogEvent("durable-logging-ready", level: .info, message: "Durable logging is ready")
    struct DurableLoggingReady {}

    @LogEvent("durable-logging-unavailable", level: .error)
    struct DurableLoggingUnavailable {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Durable logging is unavailable: \(error.description)"
        }
    }

    @LogEvent("durable-logging-history-pruned", level: .info)
    struct DurableLoggingHistoryPruned {
        @LogField(exposure: .shareable, kind: .count)
        var expiredEventCount: Int

        @LogField(exposure: .shareable, kind: .count)
        var overflowEventCount: Int

        var message: String {
            "Pruned \(expiredEventCount) expired log event(s) and \(overflowEventCount) event(s) past the size limit"
        }
    }

    @LogEvent("durable-logging-history-prune-failed", level: .warning)
    struct DurableLoggingHistoryPruneFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Failed to prune durable log history: \(error.description)"
        }
    }

    @LogEvent("cold-launch-failed", level: .error)
    struct ColdLaunchFailed {
        @LogField(exposure: .shareable, kind: .category)
        var boundary: ThrowSessionLogEvent.ColdLaunchBoundary

        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Cold launch failed at the \(boundary.rawValue) boundary"
        }
    }

    @LogEvent("software-credits-load-failed", level: .error)
    struct SoftwareCreditsLoadFailed {
        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Software credits failed to load"
        }
    }

    @LogEvent("post-launch-operation-failed", level: .error)
    struct PostLaunchOperationFailed {
        @LogField(exposure: .shareable, kind: .category)
        var operation: ThrowSessionLogEvent.PostLaunchOperation

        @LogField(exposure: .restricted, kind: .errorDetails)
        var error: LogError

        var message: String {
            "Post-launch operation failed at the \(operation.rawValue) boundary"
        }
    }
}

@LogScope("AircraftPollingLogEvent")
public enum AircraftPollingLog {
    @LogEvent("source-activated")
    struct SourceActivated {
        @LogField(exposure: .restricted, kind: .category)
        var source: AircraftSourceKind

        var message: String {
            "Aircraft polling source-activated for \(source.rawValue)"
        }
    }

    @LogEvent("receiver-metadata-fallback", level: .warning)
    struct ReceiverMetadataFallback {
        @LogField(exposure: .shareable, kind: .category)
        var source: AircraftSourceKind

        @LogField(exposure: .shareable, kind: .category)
        var failureCategory: AircraftPollingLogEvent.FailureCategory

        var message: String {
            "Aircraft polling receiver-metadata-fallback for \(source.rawValue)"
        }
    }

    @LogEvent("request-succeeded")
    struct RequestSucceeded {
        @LogField(exposure: .restricted, kind: .category)
        var source: AircraftSourceKind

        @LogField(exposure: .restricted, kind: .count)
        var requestCount: Int

        @LogField(exposure: .restricted, kind: .duration)
        var durationMilliseconds: Int

        @LogField(exposure: .restricted, kind: .technicalState)
        var httpStatus: Int?

        @LogField(exposure: .restricted, kind: .count)
        var decodedAircraftCount: Int

        var message: String {
            "Aircraft polling request-succeeded for \(source.rawValue)"
        }
    }

    @LogEvent("partial-schema-drift", level: .warning)
    struct PartialSchemaDrift {
        @LogField(exposure: .shareable, kind: .category)
        var source: AircraftSourceKind

        @LogField(exposure: .restricted, kind: .count)
        var requestCount: Int

        @LogField(exposure: .restricted, kind: .technicalState)
        var httpStatus: Int?

        @LogField(exposure: .restricted, kind: .count)
        var decodedAircraftCount: Int

        @LogField(exposure: .shareable, kind: .count)
        var malformedRecordCount: Int

        @LogField(exposure: .shareable, kind: .count)
        var missingPositionRecordCount: Int

        var message: String {
            "Aircraft polling partial-schema-drift for \(source.rawValue)"
        }
    }

    @LogEvent("request-failed", level: .warning)
    struct RequestFailed {
        @LogField(exposure: .restricted, kind: .category)
        var source: AircraftSourceKind

        @LogField(exposure: .restricted, kind: .count)
        var requestCount: Int

        @LogField(exposure: .restricted, kind: .duration)
        var durationMilliseconds: Int

        @LogField(exposure: .restricted, kind: .technicalState)
        var httpStatus: Int?

        @LogField(exposure: .restricted, kind: .category)
        var failureCategory: AircraftPollingLogEvent.FailureCategory

        var message: String {
            "Aircraft polling request-failed for \(source.rawValue)"
        }
    }

    @LogEvent("retry-scheduled", level: .warning)
    struct RetryScheduled {
        @LogField(exposure: .restricted, kind: .category)
        var source: AircraftSourceKind

        @LogField(exposure: .restricted, kind: .count)
        var requestCount: Int

        @LogField(exposure: .restricted, kind: .technicalState)
        var httpStatus: Int?

        @LogField(exposure: .restricted, kind: .count)
        var decodedAircraftCount: Int?

        @LogField(exposure: .restricted, kind: .duration)
        var backoffSeconds: Double

        @LogField(exposure: .restricted, kind: .category)
        var failureCategory: AircraftPollingLogEvent.FailureCategory

        var message: String {
            "Aircraft polling retry-scheduled for \(source.rawValue)"
        }
    }

    @LogEvent("polling-stopped")
    struct PollingStopped {
        @LogField(exposure: .restricted, kind: .category)
        var source: AircraftSourceKind

        @LogField(exposure: .restricted, kind: .count)
        var requestCount: Int

        @LogField(exposure: .restricted, kind: .count)
        var decodedAircraftCount: Int?

        var message: String {
            "Aircraft polling polling-stopped for \(source.rawValue)"
        }
    }
}

@LogScope("GeographyLogEvent")
public enum GeographyLog {
    @LogEvent("load-failed", level: .error)
    struct LoadFailed {
        @LogField(exposure: .restricted, kind: .category)
        var failureCategory: GeographyLogEvent.FailureCategory

        var message: String {
            "Bundled geography load failed: \(failureCategory.rawValue)"
        }
    }
}

@LogScope("FlightRouteLogEvent")
public enum FlightRouteLog {
    @LogEvent("enrichment-finished")
    struct EnrichmentFinished {
        @LogField(exposure: .shareable, kind: .category)
        var outcome: FlightRouteLogEvent.Outcome

        var level: LogLevel {
            outcome == .succeeded ? .info : .warning
        }

        var message: String {
            "Flight route enrichment \(outcome.rawValue)"
        }
    }
}

@LogScope("ProjectionMotionLogEvent")
public enum ProjectionMotionLog {
    @LogEvent("aggregate", level: .info, message: "Projection motion aggregate")
    struct Aggregate {
        @LogField(exposure: .restricted, kind: .domainValue)
        var framesPerSecond: Double

        @LogField(exposure: .restricted, kind: .count)
        var aircraftCount: Int

        @LogField(exposure: .restricted, kind: .domainValue)
        var usableHorizontalMotionPercent: Double?

        @LogField(exposure: .restricted, kind: .domainValue)
        var positionDerivedMotionPercent: Double?

        @LogField(exposure: .restricted, kind: .duration)
        var meanSampleAgeSeconds: Double?

        @LogField(exposure: .restricted, kind: .domainValue)
        var meanProjectedSpeedPerSecond: Double?

        @LogField(exposure: .restricted, kind: .domainValue)
        var meanCorrectionDistance: Double?

        @LogField(exposure: .restricted, kind: .domainValue)
        var previousSnapshotRetainedPercent: Double?
    }
}

public enum ThrowLog {
    public static let root = Log<ThrowRootLog>(system: .shared)
    public static let aircraft = root(AircraftPollingLog.self)
    public static let geography = root(GeographyLog.self)
    public static let flightRoutes = root(FlightRouteLog.self)
    public static let projectionMotion = root(ProjectionMotionLog.self)

    static func recordColdLaunchFailure(
        at boundary: ThrowSessionLogEvent.ColdLaunchBoundary,
        error: any Error,
        using logger: Log<ThrowSessionLog>,
    ) {
        logger.coldLaunchFailed(
            boundary: .shared(.category, boundary),
            error: .restricted(.errorDetails, error),
            attachments: [.error(error, name: "launch-error")],
        )
    }

    static func recordSoftwareCreditsLoadFailure(
        _ failure: ThrowSoftwareCreditsLoadFailure,
        using logger: Log<ThrowSessionLog>,
    ) {
        logger.softwareCreditsLoadFailed(
            error: .restricted(.errorDetails, failure.error),
            attachments: [failure.attachment],
        )
    }

    static func recordPostLaunchFailure(
        at operation: ThrowSessionLogEvent.PostLaunchOperation,
        error: any Error,
        using logger: Log<ThrowSessionLog>,
    ) {
        logger.postLaunchOperationFailed(
            operation: .shared(.category, operation),
            error: .restricted(.errorDetails, error),
            attachments: [.error(error, name: "operation-error")],
        )
    }
}

/// Records typed session failures without exposing the underlying Periscope logger.
public protocol ThrowSessionFailureLogging: Sendable {
    func recordColdLaunchFailure(
        at boundary: ThrowSessionLogEvent.ColdLaunchBoundary,
        error: any Error,
    )

    func recordPostLaunchFailure(
        at operation: ThrowSessionLogEvent.PostLaunchOperation,
        error: any Error,
    )
}

/// Drops session failures in fixtures that do not install a diagnostics pipeline.
public struct DiscardingThrowSessionFailureLogger: ThrowSessionFailureLogging {
    public init() {}

    public func recordColdLaunchFailure(
        at _: ThrowSessionLogEvent.ColdLaunchBoundary,
        error _: any Error,
    ) {}

    public func recordPostLaunchFailure(
        at _: ThrowSessionLogEvent.PostLaunchOperation,
        error _: any Error,
    ) {}
}

public protocol AircraftPollingLogging: Sendable {
    func record(_ event: AircraftPollingLogEvent)
}

public struct PeriscopeAircraftPollingLogger: AircraftPollingLogging {
    private let log: Log<AircraftPollingLog>

    public init(log: Log<AircraftPollingLog>) {
        self.log = log
    }

    public func record(_ event: AircraftPollingLogEvent) {
        switch event {
            case let .sourceActivated(event):
                log.sourceActivated(
                    source: .restricted(.category, event.source),
                )
            case let .receiverMetadataFallback(event):
                log.receiverMetadataFallback(
                    source: .shared(.category, .readsb),
                    failureCategory: .shared(.category, event.failureCategory),
                )
            case let .requestSucceeded(event):
                log.requestSucceeded(
                    source: .restricted(.category, event.source),
                    requestCount: .restricted(.count, event.requestCount),
                    durationMilliseconds: .restricted(
                        .duration,
                        event.durationMilliseconds,
                    ),
                    httpStatus: .restricted(.technicalState, event.httpStatus),
                    decodedAircraftCount: .restricted(.count, event.decodedAircraftCount),
                )
            case let .partialSchemaDrift(event):
                log.partialSchemaDrift(
                    source: .shared(.category, event.source),
                    requestCount: .restricted(.count, event.requestCount),
                    httpStatus: .restricted(.technicalState, event.httpStatus),
                    decodedAircraftCount: .restricted(.count, event.decodedAircraftCount),
                    malformedRecordCount: .shared(
                        .count,
                        event.discardedRecords.malformedRecordCount,
                    ),
                    missingPositionRecordCount: .shared(
                        .count,
                        event.discardedRecords.missingPositionRecordCount,
                    ),
                )
            case let .requestFailed(event):
                log.requestFailed(
                    source: .restricted(.category, event.source),
                    requestCount: .restricted(.count, event.requestCount),
                    durationMilliseconds: .restricted(
                        .duration,
                        event.durationMilliseconds,
                    ),
                    httpStatus: .restricted(.technicalState, event.httpStatus),
                    failureCategory: .restricted(.category, event.failureCategory),
                )
            case let .retryScheduled(event):
                log.retryScheduled(
                    source: .restricted(.category, event.source),
                    requestCount: .restricted(.count, event.requestCount),
                    httpStatus: .restricted(.technicalState, event.httpStatus),
                    decodedAircraftCount: .restricted(.count, event.decodedAircraftCount),
                    backoffSeconds: .restricted(.duration, event.backoffSeconds),
                    failureCategory: .restricted(.category, event.failureCategory),
                )
            case let .pollingStopped(event):
                log.pollingStopped(
                    source: .restricted(.category, event.source),
                    requestCount: .restricted(.count, event.requestCount),
                    decodedAircraftCount: .restricted(.count, event.decodedAircraftCount),
                )
        }
    }
}

public struct DiscardingAircraftPollingLogger: AircraftPollingLogging {
    public init() {}

    public func record(_: AircraftPollingLogEvent) {}
}

public protocol GeographyLogging: Sendable {
    func record(_ event: GeographyLogEvent)
}

public struct PeriscopeGeographyLogger: GeographyLogging {
    private let log: Log<GeographyLog>

    public init(log: Log<GeographyLog>) {
        self.log = log
    }

    public func record(_ event: GeographyLogEvent) {
        log.loadFailed(
            failureCategory: .restricted(.category, event.failureCategory),
        )
    }
}

public struct DiscardingGeographyLogger: GeographyLogging {
    public init() {}

    public func record(_: GeographyLogEvent) {}
}

public protocol FlightRouteLogging: Sendable {
    func record(_ event: FlightRouteLogEvent)
}

public struct PeriscopeFlightRouteLogger: FlightRouteLogging {
    private let log: Log<FlightRouteLog>

    public init(log: Log<FlightRouteLog>) {
        self.log = log
    }

    public func record(_ event: FlightRouteLogEvent) {
        log.enrichmentFinished(
            outcome: .shared(.category, event.outcome),
        )
    }
}

public struct DiscardingFlightRouteLogger: FlightRouteLogging {
    public init() {}

    public func record(_: FlightRouteLogEvent) {}
}

public protocol ProjectionMotionLogging: Sendable {
    func record(_ event: ProjectionMotionLogEvent)
}

public struct PeriscopeProjectionMotionLogger: ProjectionMotionLogging {
    private let log: Log<ProjectionMotionLog>

    public init(log: Log<ProjectionMotionLog>) {
        self.log = log
    }

    public func record(_ event: ProjectionMotionLogEvent) {
        log.aggregate(
            framesPerSecond: .restricted(.domainValue, event.framesPerSecond),
            aircraftCount: .restricted(.count, event.aircraftCount),
            usableHorizontalMotionPercent: .restricted(
                .domainValue,
                event.usableHorizontalMotionPercent,
            ),
            positionDerivedMotionPercent: .restricted(
                .domainValue,
                event.positionDerivedMotionPercent,
            ),
            meanSampleAgeSeconds: .restricted(.duration, event.meanSampleAgeSeconds),
            meanProjectedSpeedPerSecond: .restricted(
                .domainValue,
                event.meanProjectedSpeedPerSecond,
            ),
            meanCorrectionDistance: .restricted(
                .domainValue,
                event.meanCorrectionDistance,
            ),
            previousSnapshotRetainedPercent: .restricted(
                .domainValue,
                event.previousSnapshotRetainedPercent,
            ),
        )
    }
}

public struct DiscardingProjectionMotionLogger: ProjectionMotionLogging {
    public init() {}

    public func record(_: ProjectionMotionLogEvent) {}
}
