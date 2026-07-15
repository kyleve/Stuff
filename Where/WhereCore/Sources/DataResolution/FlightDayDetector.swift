import Foundation
import RegionKit

/// Detects days that look like a flight: consecutive GPS fixes moving at
/// cruise speed across the map. The symptom is spurious region presence — on a
/// coast-to-coast flight the fly-over states collapse to `.other` (or any
/// untracked region), so the day counts for somewhere the user only passed over
/// at 35 000 feet.
///
/// The rule, per day, over the timestamp-sorted GPS fixes in
/// `DataIssueInput.daySamples`:
///   1. A *leg* between consecutive fixes is a "flight leg" when its ground
///      speed is at least `speedThresholdKMH` **and** it spans at least
///      `minLegDistanceKM` — the distance floor rejects a close pair whose tiny
///      time delta manufactures a huge speed (GPS jitter, a teleport glitch).
///   2. A fix is a *fly-over* point when the legs on **both** sides are flight
///      legs — a point you were only passing through. A leg's endpoints (the
///      take-off / landing fixes) have a flight leg on just one side, so they
///      are not fly-over points and their region survives.
///   3. A region is *spurious* when every fix attributing the day to it is a
///      fly-over point (and it has at least one) — it exists only because the
///      flight crossed it. Endpoint and dwell regions keep at least one
///      non-fly-over fix.
///
/// It reports an issue only when at least one region would be removed and at
/// least one survives, so a day spent entirely mid-flight (no endpoint on this
/// calendar day — an overnight flight) is left alone rather than blanked.
public struct FlightDayDetector: DataIssueDetector {
    public typealias Issue = FlightDayIssue

    /// Minimum ground speed for a leg to count as flight. ~300 km/h sits well
    /// above sustained driving / rail and far below jet cruise (~800-900 km/h),
    /// so it separates the two with a wide margin.
    let speedThresholdKMH: Double
    /// Minimum leg distance for a leg to count as flight, so a close pair with a
    /// tiny time delta can't manufacture a flight-speed leg out of GPS jitter.
    let minLegDistanceKM: Double

    public init() {
        self.init(speedThresholdKMH: 300, minLegDistanceKM: 80)
    }

    @_spi(Testing)
    public init(speedThresholdKMH: Double, minLegDistanceKM: Double) {
        self.speedThresholdKMH = speedThresholdKMH
        self.minLegDistanceKM = minLegDistanceKM
    }

    public func detectIssues(in input: DataIssueInput) -> [FlightDayIssue] {
        var issues: [FlightDayIssue] = []
        for day in input.report.days {
            guard let samples = input.daySamples[day.day] else { continue }
            if let issue = flightIssue(for: day, samples: samples, attributor: input.attributor) {
                issues.append(issue)
            }
        }
        return issues
    }

    private func flightIssue(
        for day: DayPresence,
        samples: [LocationSample],
        attributor: any RegionAttributing,
    ) -> FlightDayIssue? {
        guard samples.count >= 3 else { return nil }

        // `flightLeg[i]` is the leg from `samples[i]` to `samples[i + 1]`.
        var flightLeg = [Bool](repeating: false, count: samples.count - 1)
        var peakSpeedKMH = 0.0
        for index in flightLeg.indices {
            let distanceMeters = samples[index].coordinate
                .distance(to: samples[index + 1].coordinate)
            let seconds = samples[index + 1].timestamp
                .timeIntervalSince(samples[index].timestamp)
            guard seconds > 0 else { continue }
            let speedKMH = distanceMeters / seconds * 3.6
            if speedKMH >= speedThresholdKMH, distanceMeters >= minLegDistanceKM * 1000 {
                flightLeg[index] = true
                peakSpeedKMH = max(peakSpeedKMH, speedKMH)
            }
        }

        // A region is spurious when it has at least one fly-over fix and no
        // other kind. Track both facts (plus a total fly-over count) as we walk
        // the fixes.
        var hasFlyOver: Set<Region> = []
        var hasGrounded: Set<Region> = []
        var flyOverCount = 0
        for index in samples.indices {
            let flightBefore = index > 0 && flightLeg[index - 1]
            let flightAfter = index < flightLeg.count && flightLeg[index]
            let region = attributor.region(at: samples[index].coordinate)
            if flightBefore, flightAfter {
                hasFlyOver.insert(region)
                flyOverCount += 1
            } else {
                hasGrounded.insert(region)
            }
        }

        // A flight is a *sustained* cruise, not a lone outlier: a teleport
        // glitch jumps out and straight back, leaving a single fly-over fix
        // between two flight legs. Require at least two so one bad fix — which
        // is a different kind of data issue — doesn't read as a plane.
        guard flyOverCount >= 2 else { return nil }

        let spurious = hasFlyOver.subtracting(hasGrounded)
        let removedRegions = day.regions.intersection(spurious)
        let keepRegions = day.regions.subtracting(spurious)
        guard !removedRegions.isEmpty, !keepRegions.isEmpty else { return nil }

        return FlightDayIssue(
            day: day,
            keepRegions: keepRegions,
            removedRegions: removedRegions,
            peakSpeedKMH: peakSpeedKMH,
        )
    }
}
