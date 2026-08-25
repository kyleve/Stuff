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

public enum ThrowLog {
    public static let root = Log<ThrowRootLogEvent>(system: .shared)
    public static let aircraft = root(AircraftPollingLogEvent.self)
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
