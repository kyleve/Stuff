import PeriscopeCore

public struct ThrowRootLogEvent: LogEvent {
    public static let eventName = "Throw"

    public var message: String {
        ""
    }
}

/// Process-session events for launch and durable diagnostics availability.
public enum ThrowSessionLogEvent: LogEvent, Equatable {
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

    public static let eventName = "ThrowSession"

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

    public var remoteMessage: String {
        switch self {
            case .durableLoggingReady:
                "Durable logging is ready"
            case .durableLoggingUnavailable:
                "Durable logging is unavailable"
            case .durableLoggingHistoryPruned:
                "Durable log history was pruned"
            case .durableLoggingHistoryPruneFailed:
                "Failed to prune durable log history"
            case .coldLaunchFailed:
                "Cold launch failed"
            case .softwareCreditsLoadFailed:
                "Software credits failed to load"
            case .postLaunchOperationFailed:
                "Post-launch operation failed"
        }
    }

    public var remoteFields: [RemoteLogField] {
        switch self {
            case let .durableLoggingHistoryPruned(expiredEventCount, overflowEventCount):
                [
                    RemoteLogField(
                        key: RemoteLogFieldKey("expired_event_count"),
                        value: .count(expiredEventCount),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("overflow_event_count"),
                        value: .count(overflowEventCount),
                    ),
                ]
            case let .coldLaunchFailed(boundary):
                [
                    RemoteLogField(
                        key: RemoteLogFieldKey("boundary"),
                        value: .category(RemoteLogCategory(boundary)),
                    ),
                ]
            case let .postLaunchOperationFailed(operation):
                [
                    RemoteLogField(
                        key: RemoteLogFieldKey("operation"),
                        value: .category(RemoteLogCategory(operation)),
                    ),
                ]
            case .durableLoggingReady, .durableLoggingUnavailable,
                 .durableLoggingHistoryPruneFailed, .softwareCreditsLoadFailed:
                []
        }
    }
}

public enum AircraftPollingLogEvent: Hashable, Sendable {
    public static let eventName = "AircraftPollingLogEvent"
    public static let eventVersion = 3

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

    public var remoteMessage: String {
        "Aircraft polling \(kind.rawValue)"
    }

    public var remoteFields: [RemoteLogField] {
        switch self {
            case let .partialSchemaDrift(event):
                [
                    .eventKind(kind),
                    sourceRemoteField,
                    RemoteLogField(
                        key: RemoteLogFieldKey("malformed_record_count"),
                        value: .count(event.discardedRecords.malformedRecordCount),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("missing_position_record_count"),
                        value: .count(event.discardedRecords.missingPositionRecordCount),
                    ),
                ]
            case let .receiverMetadataFallback(event):
                [
                    .eventKind(kind),
                    sourceRemoteField,
                    RemoteLogField(
                        key: RemoteLogFieldKey("failure_category"),
                        value: .category(RemoteLogCategory(event.failureCategory)),
                    ),
                ]
            case .sourceActivated, .requestSucceeded, .requestFailed, .retryScheduled,
                 .pollingStopped:
                []
        }
    }

    private var sourceRemoteField: RemoteLogField {
        RemoteLogField(
            key: RemoteLogFieldKey("source"),
            value: .category(RemoteLogCategory(source)),
        )
    }
}

/// Keeps the flat version-three payload stable while the in-memory event uses
/// case-specific state. Records from the polling coordinator stay decodable with
/// the same event name, field names, and kind vocabulary.
extension AircraftPollingLogEvent: LogEvent {
    private enum CodingKeys: String, CodingKey {
        case kind
        case source
        case requestCount
        case durationMilliseconds
        case httpStatus
        case decodedAircraftCount
        case decodingDiagnostics
        case backoffSeconds
        case failureCategory
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        let source = try container.decode(AircraftSourceKind.self, forKey: .source)
        let requestCount = try container.decode(Int.self, forKey: .requestCount)

        switch kind {
            case .sourceActivated:
                guard requestCount == 0 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .requestCount,
                        in: container,
                        debugDescription: "Source activation must precede all requests",
                    )
                }
                self = .sourceActivated(SourceActivation(source: source))
            case .receiverMetadataFallback:
                guard source == .readsb else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .source,
                        in: container,
                        debugDescription: "Receiver metadata belongs to readsb",
                    )
                }
                guard requestCount == 0 else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .requestCount,
                        in: container,
                        debugDescription: "Receiver metadata fallback must precede all requests",
                    )
                }
                self = try .receiverMetadataFallback(
                    ReceiverMetadataFallback(
                        failureCategory: container.decode(
                            FailureCategory.self,
                            forKey: .failureCategory,
                        ),
                    ),
                )
            case .requestSucceeded:
                self = try .requestSucceeded(
                    RequestSuccess(
                        source: source,
                        requestCount: requestCount,
                        durationMilliseconds: container.decode(
                            Int.self,
                            forKey: .durationMilliseconds,
                        ),
                        httpStatus: container.decodeIfPresent(Int.self, forKey: .httpStatus),
                        decodedAircraftCount: container.decode(
                            Int.self,
                            forKey: .decodedAircraftCount,
                        ),
                    ),
                )
            case .partialSchemaDrift:
                let diagnostics = try container.decode(
                    AircraftSnapshotDecodingDiagnostics.self,
                    forKey: .decodingDiagnostics,
                )
                guard let discardedRecords = diagnostics.discardedRecords else {
                    throw DecodingError.dataCorruptedError(
                        forKey: .decodingDiagnostics,
                        in: container,
                        debugDescription: "Partial schema drift must discard a record",
                    )
                }
                self = try .partialSchemaDrift(
                    PartialSchemaDrift(
                        source: source,
                        requestCount: requestCount,
                        httpStatus: container.decodeIfPresent(Int.self, forKey: .httpStatus),
                        decodedAircraftCount: container.decode(
                            Int.self,
                            forKey: .decodedAircraftCount,
                        ),
                        discardedRecords: discardedRecords,
                    ),
                )
            case .requestFailed:
                self = try .requestFailed(
                    RequestFailure(
                        source: source,
                        requestCount: requestCount,
                        durationMilliseconds: container.decode(
                            Int.self,
                            forKey: .durationMilliseconds,
                        ),
                        httpStatus: container.decodeIfPresent(Int.self, forKey: .httpStatus),
                        failureCategory: container.decode(
                            FailureCategory.self,
                            forKey: .failureCategory,
                        ),
                    ),
                )
            case .retryScheduled:
                self = try .retryScheduled(
                    RetrySchedule(
                        source: source,
                        requestCount: requestCount,
                        httpStatus: container.decodeIfPresent(Int.self, forKey: .httpStatus),
                        decodedAircraftCount: container.decodeIfPresent(
                            Int.self,
                            forKey: .decodedAircraftCount,
                        ),
                        backoffSeconds: container.decode(
                            Double.self,
                            forKey: .backoffSeconds,
                        ),
                        failureCategory: container.decode(
                            FailureCategory.self,
                            forKey: .failureCategory,
                        ),
                    ),
                )
            case .pollingStopped:
                self = try .pollingStopped(
                    PollingStop(
                        source: source,
                        requestCount: requestCount,
                        decodedAircraftCount: container.decodeIfPresent(
                            Int.self,
                            forKey: .decodedAircraftCount,
                        ),
                    ),
                )
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(source, forKey: .source)
        try container.encode(requestCount, forKey: .requestCount)

        switch self {
            case .sourceActivated:
                break
            case let .receiverMetadataFallback(event):
                try container.encode(event.failureCategory, forKey: .failureCategory)
            case let .requestSucceeded(event):
                try container.encode(event.durationMilliseconds, forKey: .durationMilliseconds)
                try container.encodeIfPresent(event.httpStatus, forKey: .httpStatus)
                try container.encode(event.decodedAircraftCount, forKey: .decodedAircraftCount)
            case let .partialSchemaDrift(event):
                try container.encodeIfPresent(event.httpStatus, forKey: .httpStatus)
                try container.encode(event.decodedAircraftCount, forKey: .decodedAircraftCount)
                try container.encode(
                    AircraftSnapshotDecodingDiagnostics(
                        malformedRecordCount: event.discardedRecords.malformedRecordCount,
                        missingPositionRecordCount: event.discardedRecords
                            .missingPositionRecordCount,
                    ),
                    forKey: .decodingDiagnostics,
                )
            case let .requestFailed(event):
                try container.encode(event.durationMilliseconds, forKey: .durationMilliseconds)
                try container.encodeIfPresent(event.httpStatus, forKey: .httpStatus)
                try container.encode(event.failureCategory, forKey: .failureCategory)
            case let .retryScheduled(event):
                try container.encodeIfPresent(event.httpStatus, forKey: .httpStatus)
                try container.encodeIfPresent(
                    event.decodedAircraftCount,
                    forKey: .decodedAircraftCount,
                )
                try container.encode(event.backoffSeconds, forKey: .backoffSeconds)
                try container.encode(event.failureCategory, forKey: .failureCategory)
            case let .pollingStopped(event):
                try container.encodeIfPresent(
                    event.decodedAircraftCount,
                    forKey: .decodedAircraftCount,
                )
        }
    }
}

/// A redacted failure loading Throw's bundled geographic archive.
public struct GeographyLogEvent: LogEvent {
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

    public var remoteMessage: String {
        "Bundled geography load failed"
    }
}

/// A redacted outcome from optional flight-route enrichment.
public struct FlightRouteLogEvent: LogEvent {
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

    public var remoteMessage: String {
        message
    }
}

/// A privacy-safe aggregate sample of the projection motion pipeline.
public struct ProjectionMotionLogEvent: LogEvent, Equatable {
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

    public var remoteMessage: String {
        message
    }
}

public enum ThrowLog {
    public static let root = Log<ThrowRootLogEvent>(system: .shared)
    public static let aircraft = root(AircraftPollingLogEvent.self)
    public static let geography = root(GeographyLogEvent.self)
    public static let flightRoutes = root(FlightRouteLogEvent.self)
    public static let projectionMotion = root(ProjectionMotionLogEvent.self)

    static func recordColdLaunchFailure(
        at boundary: ThrowSessionLogEvent.ColdLaunchBoundary,
        error: any Error,
        using logger: Log<ThrowSessionLogEvent>,
    ) {
        logger(attachments: [.error(error, name: "launch-error")]) {
            .coldLaunchFailed(boundary: boundary)
        }
    }

    static func recordSoftwareCreditsLoadFailure(
        _ failure: ThrowSoftwareCreditsLoadFailure,
        using logger: Log<ThrowSessionLogEvent>,
    ) {
        logger(attachments: [failure.attachment]) {
            .softwareCreditsLoadFailed
        }
    }

    static func recordPostLaunchFailure(
        at operation: ThrowSessionLogEvent.PostLaunchOperation,
        error: any Error,
        using logger: Log<ThrowSessionLogEvent>,
    ) {
        logger(attachments: [.error(error, name: "operation-error")]) {
            .postLaunchOperationFailed(operation: operation)
        }
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
    private let log: Log<AircraftPollingLogEvent>

    public init(log: Log<AircraftPollingLogEvent>) {
        self.log = log
    }

    public func record(_ event: AircraftPollingLogEvent) {
        log { event }
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
    private let log: Log<GeographyLogEvent>

    public init(log: Log<GeographyLogEvent>) {
        self.log = log
    }

    public func record(_ event: GeographyLogEvent) {
        log { event }
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
    private let log: Log<FlightRouteLogEvent>

    public init(log: Log<FlightRouteLogEvent>) {
        self.log = log
    }

    public func record(_ event: FlightRouteLogEvent) {
        log { event }
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
    private let log: Log<ProjectionMotionLogEvent>

    public init(log: Log<ProjectionMotionLogEvent>) {
        self.log = log
    }

    public func record(_ event: ProjectionMotionLogEvent) {
        log { event }
    }
}

public struct DiscardingProjectionMotionLogger: ProjectionMotionLogging {
    public init() {}

    public func record(_: ProjectionMotionLogEvent) {}
}
