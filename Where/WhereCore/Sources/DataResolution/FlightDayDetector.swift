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
///      `minLegSeconds` — the duration floor rejects a close pair whose tiny
///      time delta manufactures a huge speed (GPS jitter, a teleport glitch),
///      without rejecting a densely-sampled cruise (significant-change fires
///      every few minutes, so a real cruise leg is only ~70 km even though it's
///      minutes long — a distance floor would wrongly drop those).
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
    /// Minimum leg *duration* for a leg to count as flight, so a sub-minute GPS
    /// glitch (a huge implied speed over a few seconds) can't manufacture a
    /// flight leg. Cruise fixes arrive every few minutes, so real flight legs
    /// clear this comfortably — and unlike a distance floor it doesn't drop a
    /// densely-sampled cruise's short (~70 km) five-minute legs.
    let minLegSeconds: TimeInterval

    public init() {
        self.init(speedThresholdKMH: 300, minLegSeconds: 60)
    }

    @_spi(Testing)
    public init(speedThresholdKMH: Double, minLegSeconds: TimeInterval) {
        self.speedThresholdKMH = speedThresholdKMH
        self.minLegSeconds = minLegSeconds
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
        let fixes = Self.coalescingSimultaneous(samples)
        guard fixes.count >= 3 else { return nil }

        // `flightLeg[i]` is the leg from `fixes[i]` to `fixes[i + 1]`.
        var flightLeg = [Bool](repeating: false, count: fixes.count - 1)
        var peakSpeedKMH = 0.0
        for index in flightLeg.indices {
            let distanceMeters = fixes[index].coordinate
                .distance(to: fixes[index + 1].coordinate)
            let seconds = fixes[index + 1].timestamp
                .timeIntervalSince(fixes[index].timestamp)
            guard seconds >= minLegSeconds else { continue }
            let speedKMH = distanceMeters / seconds * 3.6
            if speedKMH >= speedThresholdKMH {
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
        for index in fixes.indices {
            let flightBefore = index > 0 && flightLeg[index - 1]
            let flightAfter = index < flightLeg.count && flightLeg[index]
            let region = attributor.region(at: fixes[index].coordinate)
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

    /// Fixes closer together in time than this are treated as one reading.
    private static let coalesceWindowSeconds: TimeInterval = 1

    /// Collapse runs of near-simultaneous fixes to a single, most-accurate
    /// representative. CoreLocation routinely emits a `CLVisit` *and* a
    /// significant-change update at the *same* instant, so a day's samples carry
    /// exact-timestamp duplicates. A zero-duration leg between two such fixes has
    /// no speed, so it isn't a flight leg — and left in, it breaks a fly-over
    /// run: the cruise fix beside a duplicate reads as "grounded" (one adjacent
    /// leg has no speed), its region stops looking spurious, and a real flight
    /// goes unflagged. Collapsing by *time* (not distance) leaves genuine dwells
    /// — fixes minutes apart at one spot — intact, so a real layover still
    /// grounds its region.
    private static func coalescingSimultaneous(_ samples: [LocationSample]) -> [LocationSample] {
        var result: [LocationSample] = []
        for sample in samples {
            if let last = result.last,
               sample.timestamp.timeIntervalSince(last.timestamp) < coalesceWindowSeconds
            {
                // Same instant as the representative — keep the more accurate fix.
                if sample.horizontalAccuracy < last.horizontalAccuracy {
                    result[result.count - 1] = sample
                }
            } else {
                result.append(sample)
            }
        }
        return result
    }
}
