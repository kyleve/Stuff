import PeriscopeCore

/// PII-free outcomes for foreground region resolution.
enum CurrentRegionResolverLog: LogEvent {
    enum Kind: String, CaseIterable, Codable {
        case finished
    }

    enum Reason: String, CaseIterable, Codable {
        case resolved
        case recordingInactive = "recording-inactive"
        case invalidFix = "invalid-fix"
        case staleFix = "stale-fix"
        case excessiveUncertainty = "excessive-uncertainty"
        case boundaryUncertainty = "boundary-uncertainty"
        case outsideTrackedRegions = "outside-tracked-regions"
        case authorizationUnavailable = "authorization-unavailable"
        case preciseLocationDisabled = "precise-location-disabled"
        case timeout
        case providerFailure = "provider-failure"
        case cancellation
    }

    enum AgeBucket: String, CaseIterable, Codable {
        case unavailable
        case fresh = "0-10s"
        case recent = "11-60s"
        case stale = "over-60s"
    }

    enum AccuracyBucket: String, CaseIterable, Codable {
        case unavailable
        case invalid
        case precise = "0-100m"
        case kilometer = "101-1000m"
        case excessive = "over-1000m"
    }

    enum SpanName: Hashable {
        case resolve
    }

    case finished(reason: Reason, ageBucket: AgeBucket, accuracyBucket: AccuracyBucket)

    static let eventName = "CurrentRegionResolver"

    var level: LogLevel {
        switch self {
            case let .finished(reason, _, _):
                reason == .resolved ? .info : .warning
        }
    }

    var message: String {
        switch self {
            case let .finished(reason, ageBucket, accuracyBucket):
                "Current region resolution finished: \(reason.rawValue), age \(ageBucket.rawValue), accuracy \(accuracyBucket.rawValue)"
        }
    }

    var remoteFields: [RemoteLogField] {
        switch self {
            case let .finished(reason, ageBucket, accuracyBucket):
                [
                    .eventKind(Kind.finished),
                    RemoteLogField(
                        key: RemoteLogFieldKey("reason"),
                        value: .category(RemoteLogCategory(reason)),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("age_bucket"),
                        value: .category(RemoteLogCategory(ageBucket)),
                    ),
                    RemoteLogField(
                        key: RemoteLogFieldKey("accuracy_bucket"),
                        value: .category(RemoteLogCategory(accuracyBucket)),
                    ),
                ]
        }
    }
}
