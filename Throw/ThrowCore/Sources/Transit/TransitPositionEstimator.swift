import Foundation

public struct TransitVehicleEstimate: Hashable, Sendable {
    public let run: TransitRunObservation
    public let route: TransitRoute
    public let coordinate: GeoCoordinate
    public let motion: TransitProjectionMotion?
    public let confidence: TransitPositionConfidence
    public let destination: TransitStop?
    public let nextStop: TransitStop

    public init(
        run: TransitRunObservation,
        route: TransitRoute,
        coordinate: GeoCoordinate,
        motion: TransitProjectionMotion?,
        confidence: TransitPositionConfidence,
        destination: TransitStop?,
        nextStop: TransitStop,
    ) {
        self.run = run
        self.route = route
        self.coordinate = coordinate
        self.motion = motion
        self.confidence = confidence
        self.destination = destination
        self.nextStop = nextStop
    }
}

/// Matches MTA Trip Updates to static patterns and estimates positions along GTFS shapes.
public struct TransitPositionEstimator: Sendable {
    private var priorNextStopByRun: [TransitRunID: TransitStopID] = [:]

    public init() {}

    public mutating func reset() {
        priorNextStopByRun = [:]
    }

    public mutating func estimates(
        snapshots: [TransitPartitionSnapshot],
        schedule: TransitSchedule,
        at date: Date,
    ) -> [TransitVehicleEstimate] {
        var nextHistory: [TransitRunID: TransitStopID] = [:]
        let result = snapshots.flatMap(\.runs).compactMap { run -> TransitVehicleEstimate? in
            guard let nextPrediction = run.upcomingStops.first,
                  let nextStop = stop(nextPrediction.stopID, in: schedule),
                  let route = schedule.routes[run.routeID],
                  let pattern = pattern(for: run, in: schedule),
                  let nextIndex = pattern.stops.firstIndex(where: {
                      $0.stopID.parentStationID == nextPrediction.stopID.parentStationID
                  }),
                  let shape = schedule.shapes[pattern.shapeID], shape.count >= 2
            else { return nil }
            nextHistory[run.id] = nextPrediction.stopID

            let destination = pattern.stops.last.flatMap { stop($0.stopID, in: schedule) }
            guard nextIndex > 0 else {
                return TransitVehicleEstimate(
                    run: run,
                    route: route,
                    coordinate: nextStop.coordinate,
                    motion: nil,
                    confidence: .scheduleInferred,
                    destination: destination,
                    nextStop: nextStop,
                )
            }
            let previousPatternStop = pattern.stops[nextIndex - 1]
            let nextPatternStop = pattern.stops[nextIndex]
            let startDistance = shapeDistance(
                for: previousPatternStop,
                stop: stop(previousPatternStop.stopID, in: schedule),
                shape: shape,
            )
            let endDistance = shapeDistance(
                for: nextPatternStop,
                stop: nextStop,
                shape: shape,
            )
            guard let startDistance, let endDistance,
                  endDistance > startDistance else { return nil }
            let points = motionPoints(
                shape: shape,
                startDistance: startDistance,
                endDistance: endDistance,
            )
            guard points.count >= 2 else { return nil }

            let scheduledDuration = max(
                nextPatternStop.arrivalSeconds - previousPatternStop.departureSeconds,
                30,
            )
            let arrival = nextPrediction.arrival ?? nextPrediction.departure
            let end = arrival ?? run.observedAt.addingTimeInterval(TimeInterval(scheduledDuration))
            let previouslyExpected = priorNextStopByRun[run.id]
            let feedTracked = previouslyExpected?.parentStationID == previousPatternStop.stopID
                .parentStationID
            let start = feedTracked
                ? run.observedAt
                : end.addingTimeInterval(-TimeInterval(scheduledDuration))
            let confidence: TransitPositionConfidence = feedTracked ? .feedTracked :
                .scheduleInferred
            guard end > start else {
                return TransitVehicleEstimate(
                    run: run,
                    route: route,
                    coordinate: nextStop.coordinate,
                    motion: nil,
                    confidence: confidence,
                    destination: destination,
                    nextStop: nextStop,
                )
            }
            let motion = TransitProjectionMotion(points: points, startsAt: start, endsAt: end)
            let coordinate = coordinate(in: motion, at: date)
            return TransitVehicleEstimate(
                run: run,
                route: route,
                coordinate: coordinate,
                motion: motion,
                confidence: confidence,
                destination: destination,
                nextStop: nextStop,
            )
        }
        priorNextStopByRun = nextHistory
        return result
    }

    private func pattern(
        for run: TransitRunObservation,
        in schedule: TransitSchedule,
    ) -> TransitTripPattern? {
        if let tripID = run.tripID,
           let exact = schedule.tripPatterns.first(where: { $0.tripID == tripID })
        {
            return exact
        }
        let remaining = run.upcomingStops.map(\.stopID.parentStationID)
        return schedule.tripPatterns
            .filter { pattern in
                pattern.routeID == run.routeID &&
                    (run.direction == nil || pattern.direction == run.direction)
            }
            .max { lhs, rhs in
                matchCount(pattern: lhs, remainingStops: remaining) <
                    matchCount(pattern: rhs, remainingStops: remaining)
            }
    }

    private func matchCount(
        pattern: TransitTripPattern,
        remainingStops: [TransitStopID],
    ) -> Int {
        guard let first = remainingStops.first,
              let index = pattern.stops.firstIndex(where: {
                  $0.stopID.parentStationID == first
              })
        else { return 0 }
        return zip(pattern.stops[index...], remainingStops).prefix { pair in
            pair.0.stopID.parentStationID == pair.1
        }.count
    }

    private func stop(_ id: TransitStopID, in schedule: TransitSchedule) -> TransitStop? {
        schedule.stops[id] ?? schedule.stops[id.parentStationID]
    }

    private func shapeDistance(
        for patternStop: TransitTripPattern.Stop,
        stop: TransitStop?,
        shape: [TransitShapePoint],
    ) -> Double? {
        if let distance = patternStop.shapeDistanceTraveled { return distance }
        guard let stop else { return nil }
        return shape.min { lhs, rhs in
            squaredDistance(lhs.coordinate, stop.coordinate) <
                squaredDistance(rhs.coordinate, stop.coordinate)
        }?.distanceTraveled
    }

    private func squaredDistance(_ lhs: GeoCoordinate, _ rhs: GeoCoordinate) -> Double {
        let latitude = lhs.latitude - rhs.latitude
        let longitude = lhs.longitude - rhs.longitude
        return latitude * latitude + longitude * longitude
    }

    private func motionPoints(
        shape: [TransitShapePoint],
        startDistance: Double,
        endDistance: Double,
    ) -> [TransitMotionPoint] {
        guard let start = shapePoint(at: startDistance, in: shape),
              let end = shapePoint(at: endDistance, in: shape)
        else { return [] }
        let points = [start] + shape.filter {
            $0.distanceTraveled > startDistance && $0.distanceTraveled < endDistance
        } + [end]
        return points.map {
            TransitMotionPoint(
                coordinate: $0.coordinate,
                distance: max(0, $0.distanceTraveled - startDistance),
            )
        }
    }

    private func shapePoint(
        at distance: Double,
        in shape: [TransitShapePoint],
    ) -> TransitShapePoint? {
        guard let first = shape.first, let last = shape.last,
              distance >= first.distanceTraveled, distance <= last.distanceTraveled
        else { return nil }
        guard let upperIndex = shape.firstIndex(where: { $0.distanceTraveled >= distance })
        else { return nil }
        let upper = shape[upperIndex]
        guard upper.distanceTraveled != distance, upperIndex > 0 else { return upper }
        let lower = shape[upperIndex - 1]
        let span = upper.distanceTraveled - lower.distanceTraveled
        guard span > 0 else { return upper }
        let progress = (distance - lower.distanceTraveled) / span
        return TransitShapePoint(
            coordinate: interpolated(lower.coordinate, upper.coordinate, progress: progress),
            distanceTraveled: distance,
        )
    }

    private func coordinate(in motion: TransitProjectionMotion, at date: Date) -> GeoCoordinate {
        guard let first = motion.points.first, let last = motion.points.last else {
            preconditionFailure("Validated transit motion has endpoints")
        }
        let progress = min(max(
            date.timeIntervalSince(motion.startsAt) /
                motion.endsAt.timeIntervalSince(motion.startsAt),
            0,
        ), 1)
        let target = first.distance + (last.distance - first.distance) * progress
        guard let upper = motion.points.firstIndex(where: { $0.distance >= target }), upper > 0
        else { return upperBoundCoordinate(first: first, last: last, progress: progress) }
        let lowerPoint = motion.points[upper - 1]
        let upperPoint = motion.points[upper]
        let span = upperPoint.distance - lowerPoint.distance
        guard span > 0 else { return upperPoint.coordinate }
        let local = (target - lowerPoint.distance) / span
        return interpolated(lowerPoint.coordinate, upperPoint.coordinate, progress: local)
    }

    private func upperBoundCoordinate(
        first: TransitMotionPoint,
        last: TransitMotionPoint,
        progress: Double,
    ) -> GeoCoordinate {
        progress >= 1 ? last.coordinate : first.coordinate
    }

    private func interpolated(
        _ lhs: GeoCoordinate,
        _ rhs: GeoCoordinate,
        progress: Double,
    ) -> GeoCoordinate {
        let longitudeDelta = normalizedLongitude(rhs.longitude - lhs.longitude)
        let longitude = normalizedLongitude(lhs.longitude + longitudeDelta * progress)
        do {
            return try GeoCoordinate(
                latitude: lhs.latitude + (rhs.latitude - lhs.latitude) * progress,
                longitude: longitude,
            )
        } catch {
            assertionFailure("Interpolation between validated coordinates must remain valid")
            return rhs
        }
    }

    private func normalizedLongitude(_ value: Double) -> Double {
        var result = value.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }
}
