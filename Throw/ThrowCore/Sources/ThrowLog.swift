import PeriscopeCore

public struct ThrowRootLogEvent: LogEvent {
    public static let eventName = "Throw"

    public var message: String {
        ""
    }
}

public struct AircraftPollingLogEvent: LogEvent {
    public enum Kind: String, Codable, Hashable, Sendable {
        case sourceActivated = "source-activated"
        case requestSucceeded = "request-succeeded"
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

    public let kind: Kind
    public let source: AircraftSourceKind
    public let requestCount: Int
    public let durationMilliseconds: Int?
    public let httpStatus: Int?
    public let decodedAircraftCount: Int?
    public let backoffSeconds: Double?
    public let failureCategory: FailureCategory?

    public init(
        kind: Kind,
        source: AircraftSourceKind,
        requestCount: Int,
        durationMilliseconds: Int?,
        httpStatus: Int?,
        decodedAircraftCount: Int?,
        backoffSeconds: Double?,
        failureCategory: FailureCategory?,
    ) {
        self.kind = kind
        self.source = source
        self.requestCount = requestCount
        self.durationMilliseconds = durationMilliseconds
        self.httpStatus = httpStatus
        self.decodedAircraftCount = decodedAircraftCount
        self.backoffSeconds = backoffSeconds
        self.failureCategory = failureCategory
    }

    public var level: LogLevel {
        switch kind {
            case .sourceActivated, .requestSucceeded, .pollingStopped:
                .info
            case .requestFailed, .retryScheduled:
                .warning
        }
    }

    public var message: String {
        "Aircraft polling \(kind.rawValue) for \(source.rawValue)"
    }

    public var remoteMessage: String {
        "Aircraft polling \(kind.rawValue)"
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

public enum ThrowLog {
    public static let root = Log<ThrowRootLogEvent>(system: .shared)
    public static let aircraft = root(AircraftPollingLogEvent.self)
    public static let geography = root(GeographyLogEvent.self)
    public static let flightRoutes = root(FlightRouteLogEvent.self)
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
