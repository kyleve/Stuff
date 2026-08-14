import PeriscopeCore

/// PII-free outcomes for foreground region resolution.
@LogScope("CurrentRegionResolver")
enum CurrentRegionResolverLog {
    enum Reason: String, CaseIterable, Codable, Sendable {
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

    enum AgeBucket: String, CaseIterable, Codable, Sendable {
        case unavailable
        case fresh = "0-10s"
        case recent = "11-60s"
        case stale = "over-60s"
    }

    enum AccuracyBucket: String, CaseIterable, Codable, Sendable {
        case unavailable
        case invalid
        case precise = "0-100m"
        case kilometer = "101-1000m"
        case excessive = "over-1000m"
    }

    enum SpanName: Hashable {
        case resolve
    }

    @LogEvent("finished")
    struct Finished {
        @LogField("reason", exposure: .shareable, kind: .category)
        var reason: Reason

        @LogField("age_bucket", exposure: .shareable, kind: .category)
        var ageBucket: AgeBucket

        @LogField("accuracy_bucket", exposure: .shareable, kind: .category)
        var accuracyBucket: AccuracyBucket

        var level: LogLevel {
            reason == .resolved ? .info : .warning
        }

        var message: String {
            "Current region resolution finished: \(reason.rawValue), age \(ageBucket.rawValue), accuracy \(accuracyBucket.rawValue)"
        }
    }
}
