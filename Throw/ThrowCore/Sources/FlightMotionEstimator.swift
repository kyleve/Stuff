import Foundation

/// Reconciles provider motion with consecutive positions without retaining
/// aircraft history beyond the active runtime.
struct FlightMotionEstimator {
    private static let minimumDerivedSpeedKnots = 10.0
    private static let maximumDerivedSpeedKnots = 1200.0
    private static let maximumTranslationInterval: TimeInterval = 10 * 60
    private static let maximumTurnInterval: TimeInterval = 30
    private static let minimumTurnSpeedKnots = 60.0
    private static let maximumTurnRateDegreesPerSecond = 3.0

    private struct Entry {
        let coordinate: GeoCoordinate
        let observedAt: Date
        let motion: AircraftMotion
    }

    private let engine = ProjectionEngine()
    private var entries: [AircraftID: Entry] = [:]
    private var source: AircraftSourceKind?

    mutating func motions(for snapshot: AircraftSnapshot) throws -> [AircraftID: AircraftMotion] {
        if source != snapshot.source {
            reset()
            source = snapshot.source
        }

        var nextEntries: [AircraftID: Entry] = [:]
        var motions: [AircraftID: AircraftMotion] = [:]
        nextEntries.reserveCapacity(snapshot.observations.count)
        motions.reserveCapacity(snapshot.observations.count)

        for (index, observation) in snapshot.observations.enumerated() {
            if index.isMultiple(of: 64) { try Task.checkCancellation() }
            let previous = entries[observation.id]
            let motion = try resolvedMotion(for: observation, previous: previous)
            motions[observation.id] = motion
            nextEntries[observation.id] = Entry(
                coordinate: observation.coordinate,
                observedAt: observation.positionObservedAt,
                motion: motion,
            )
        }
        entries = nextEntries
        return motions
    }

    private mutating func reset() {
        entries = [:]
        source = nil
    }

    private func resolvedMotion(
        for observation: AircraftObservation,
        previous: Entry?,
    ) throws -> AircraftMotion {
        let reported = AircraftMotion.reported(by: observation)
        guard let previous else { return reported }
        let interval = observation.positionObservedAt.timeIntervalSince(previous.observedAt)
        guard interval > 0 else {
            guard observation.coordinate == previous.coordinate else { return reported }
            if reported.horizontalSource == .unavailable,
               previous.motion.horizontalSource == .positionDerived
            {
                return try AircraftMotion(
                    groundTrack: previous.motion.groundTrack,
                    groundSpeedKnots: previous.motion.groundSpeedKnots,
                    verticalRateFeetPerMinute: reported.verticalRateFeetPerMinute,
                    turnRateDegreesPerSecond: previous.motion.turnRateDegreesPerSecond,
                    horizontalSource: .positionDerived,
                )
            }
            let reportsSameMotion = reported.groundTrack == previous.motion.groundTrack &&
                reported.groundSpeedKnots == previous.motion.groundSpeedKnots &&
                reported.verticalRateFeetPerMinute == previous.motion.verticalRateFeetPerMinute
            return reportsSameMotion ? previous.motion : reported
        }

        let measured = try measuredHorizontalMotion(
            from: previous.coordinate,
            to: observation.coordinate,
            interval: interval,
        )
        let horizontal = reconciledHorizontalMotion(
            reported: reported,
            measured: measured,
            interval: interval,
        )
        let turnRate = turnRate(
            previous: previous.motion,
            currentTrack: horizontal.track,
            currentSpeedKnots: horizontal.speedKnots,
            interval: interval,
            currentSource: horizontal.source,
        )
        return try AircraftMotion(
            groundTrack: horizontal.track,
            groundSpeedKnots: horizontal.speedKnots,
            verticalRateFeetPerMinute: reported.verticalRateFeetPerMinute,
            turnRateDegreesPerSecond: turnRate,
            horizontalSource: horizontal.source,
        )
    }

    private func measuredHorizontalMotion(
        from previous: GeoCoordinate,
        to current: GeoCoordinate,
        interval: TimeInterval,
    ) throws -> MeasuredHorizontalMotion? {
        guard interval <= Self.maximumTranslationInterval else { return nil }
        let position = try engine.greatCirclePosition(from: previous, to: current)
        let speedKnots = position.distance.value * 3600 / interval
        guard Self.minimumDerivedSpeedKnots ... Self.maximumDerivedSpeedKnots ~= speedKnots
        else { return nil }
        return MeasuredHorizontalMotion(
            track: position.initialBearing,
            speedKnots: speedKnots,
        )
    }

    private func reconciledHorizontalMotion(
        reported: AircraftMotion,
        measured: MeasuredHorizontalMotion?,
        interval: TimeInterval,
    ) -> HorizontalMotion {
        guard let measured else {
            return HorizontalMotion(
                track: reported.groundTrack,
                speedKnots: reported.groundSpeedKnots,
                source: reported.horizontalSource,
            )
        }
        guard let reportedTrack = reported.groundTrack,
              let reportedSpeed = reported.groundSpeedKnots
        else {
            return HorizontalMotion(
                track: measured.track,
                speedKnots: measured.speedKnots,
                source: .positionDerived,
            )
        }
        if isClearlyInconsistent(
            reportedTrack: reportedTrack,
            reportedSpeed: reportedSpeed,
            measured: measured,
            interval: interval,
        ) {
            return HorizontalMotion(
                track: measured.track,
                speedKnots: measured.speedKnots,
                source: .positionDerived,
            )
        }
        return HorizontalMotion(
            track: reportedTrack,
            speedKnots: reportedSpeed,
            source: .provider,
        )
    }

    private func isClearlyInconsistent(
        reportedTrack: Bearing,
        reportedSpeed: Double,
        measured: MeasuredHorizontalMotion,
        interval: TimeInterval,
    ) -> Bool {
        let slowFastMismatch = (reportedSpeed < 30 && measured.speedKnots >= 80) ||
            (measured.speedKnots < 30 && reportedSpeed >= 80)
        let ratio = max(reportedSpeed, measured.speedKnots) /
            max(1, min(reportedSpeed, measured.speedKnots))
        let speedMismatch = ratio > 3 && abs(reportedSpeed - measured.speedKnots) > 150
        let trackMismatch = interval <= 60 &&
            courseDifference(reportedTrack, measured.track) > 100 &&
            min(reportedSpeed, measured.speedKnots) >= 80
        return slowFastMismatch || speedMismatch || trackMismatch
    }

    private func turnRate(
        previous: AircraftMotion,
        currentTrack: Bearing?,
        currentSpeedKnots: Double?,
        interval: TimeInterval,
        currentSource: AircraftHorizontalMotionSource,
    ) -> Double? {
        guard interval <= Self.maximumTurnInterval,
              previous.horizontalSource == .provider,
              currentSource == .provider,
              let previousTrack = previous.groundTrack,
              let currentTrack,
              let currentSpeedKnots,
              currentSpeedKnots >= Self.minimumTurnSpeedKnots
        else { return nil }
        let rate = signedCourseDifference(from: previousTrack, to: currentTrack) / interval
        guard abs(rate) <= Self.maximumTurnRateDegreesPerSecond else { return nil }
        return abs(rate) >= 0.03 ? rate : nil
    }

    private func courseDifference(_ lhs: Bearing, _ rhs: Bearing) -> Double {
        abs(signedCourseDifference(from: lhs, to: rhs))
    }

    private func signedCourseDifference(from: Bearing, to: Bearing) -> Double {
        var difference = (to.degrees - from.degrees).truncatingRemainder(dividingBy: 360)
        if difference > 180 { difference -= 360 }
        if difference < -180 { difference += 360 }
        return difference
    }

    private struct HorizontalMotion {
        let track: Bearing?
        let speedKnots: Double?
        let source: AircraftHorizontalMotionSource
    }

    private struct MeasuredHorizontalMotion {
        let track: Bearing
        let speedKnots: Double
    }
}
