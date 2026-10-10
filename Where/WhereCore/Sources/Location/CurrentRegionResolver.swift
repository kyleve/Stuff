import Foundation
import RegionKit

/// Resolves the device's current tracked region while automatic recording is authorized.
public struct CurrentRegionResolver: Sendable {
    private static let maximumFixAge: TimeInterval = 60
    private static let maximumHorizontalAccuracy = 1000.0
    private static let logger = WhereLog.location(CurrentRegionResolverLog.self)

    private let ingestor: LocationIngestor
    private let attributor: any RegionAttributing

    init(ingestor: LocationIngestor, attributor: any RegionAttributing) {
        self.ingestor = ingestor
        self.attributor = attributor
    }

    /// Returns a tracked region only when a fresh live fix is confidently
    /// attributable inside its boundary.
    public func resolve(now: Date) async -> CurrentRegionResolution {
        await Self.logger.measure(.resolve, budget: .seconds(10)) {
            await resolveMeasured(now: now)
        }
    }

    private func resolveMeasured(now: Date) async -> CurrentRegionResolution {
        guard await ingestor.isRecordingAuthorized else {
            return finish(.unavailable(.recordingInactive), sample: nil, now: now)
        }
        let locationResult = await ingestor.currentLocation()
        guard !Task.isCancelled else {
            return finish(.unavailable(.location(.cancellation)), sample: nil, now: now)
        }
        let sample: LocationSample
        switch locationResult {
            case let .success(locationSample):
                sample = locationSample
            case let .unavailable(reason):
                return finish(.unavailable(.location(reason)), sample: nil, now: now)
        }
        guard await ingestor.isRecordingAuthorized else {
            return finish(.unavailable(.recordingInactive), sample: sample, now: now)
        }
        guard sample.horizontalAccuracy >= 0 else {
            return finish(.unavailable(.invalidFix), sample: sample, now: now)
        }
        guard abs(now.timeIntervalSince(sample.timestamp)) <= Self.maximumFixAge else {
            return finish(.unavailable(.staleFix), sample: sample, now: now)
        }
        guard sample.horizontalAccuracy <= Self.maximumHorizontalAccuracy else {
            return finish(.unavailable(.excessiveUncertainty), sample: sample, now: now)
        }

        let region = attributor.region(at: sample.coordinate)
        guard region != .other else {
            return finish(.unavailable(.outsideTrackedRegions), sample: sample, now: now)
        }
        guard let boundaryDistance = attributor.distanceToBoundary(
            of: region,
            from: sample.coordinate,
        ) else {
            return finish(.unavailable(.outsideTrackedRegions), sample: sample, now: now)
        }
        guard sample.horizontalAccuracy < boundaryDistance else {
            return finish(.unavailable(.boundaryUncertainty), sample: sample, now: now)
        }
        return finish(.resolved(region), sample: sample, now: now)
    }

    private func finish(
        _ resolution: CurrentRegionResolution,
        sample: LocationSample?,
        now: Date,
    ) -> CurrentRegionResolution {
        Self.logger.finished(
            reason: .shared(.category, reasonCode(for: resolution)),
            ageBucket: .shared(.category, ageBucket(for: sample, now: now)),
            accuracyBucket: .shared(.category, accuracyBucket(for: sample)),
        )
        return resolution
    }

    private func reasonCode(
        for resolution: CurrentRegionResolution,
    ) -> CurrentRegionResolverLog.Reason {
        switch resolution {
            case .resolved: .resolved
            case let .unavailable(reason):
                switch reason {
                    case .recordingInactive: .recordingInactive
                    case .invalidFix: .invalidFix
                    case .staleFix: .staleFix
                    case .excessiveUncertainty: .excessiveUncertainty
                    case .boundaryUncertainty: .boundaryUncertainty
                    case .outsideTrackedRegions: .outsideTrackedRegions
                    case let .location(reason):
                        switch reason {
                            case .authorizationUnavailable: .authorizationUnavailable
                            case .preciseLocationDisabled: .preciseLocationDisabled
                            case .timeout: .timeout
                            case .providerFailure: .providerFailure
                            case .cancellation: .cancellation
                        }
                }
        }
    }

    private func ageBucket(
        for sample: LocationSample?,
        now: Date,
    ) -> CurrentRegionResolverLog.AgeBucket {
        guard let sample else { return .unavailable }
        let age = abs(now.timeIntervalSince(sample.timestamp))
        if age <= 10 { return .fresh }
        if age <= 60 { return .recent }
        return .stale
    }

    private func accuracyBucket(
        for sample: LocationSample?,
    ) -> CurrentRegionResolverLog.AccuracyBucket {
        guard let sample else { return .unavailable }
        if sample.horizontalAccuracy < 0 { return .invalid }
        if sample.horizontalAccuracy <= 100 { return .precise }
        if sample.horizontalAccuracy <= 1000 { return .kilometer }
        return .excessive
    }
}
