import Foundation

/// Detects days carrying an `.other` attribution whose GPS coordinates actually
/// sit just outside a primary region's border — likely GPS jitter near a
/// boundary — and reports the nearest region as a `BorderDriftIssue`.
///
/// This covers both a day attributed *only* to `.other` and a "mixed" day where
/// a real region picked up a stray `.other` from a couple of drifted fixes
/// (e.g. New York plus a point that jittered across a river): the spurious
/// `.other` pollutes the data even when the day already counts correctly, and
/// the fix (`BorderDriftIssue.resolution`) relabels it away.
///
/// For each day containing `.other` it measures every recorded coordinate's
/// distance to each primary region's boundary (only coordinates the attributor
/// still resolves to `.other`, so genuinely-inside points are ignored) and,
/// when the closest is within `input.driftThresholdMeters`, flags the day with
/// that region and distance.
public struct BorderDriftDetector: DataIssueDetector {
    public typealias Issue = BorderDriftIssue

    public init() {}

    public func detectIssues(in input: DataIssueInput) -> [BorderDriftIssue] {
        guard !input.primaryRegions.isEmpty else { return [] }

        var issues: [BorderDriftIssue] = []
        for day in input.report.days where day.regions.contains(.other) {
            guard let coordinates = input.otherDayCoordinates[day.date],
                  !coordinates.isEmpty else { continue }

            var bestRegion: Region?
            var bestDistance = Double.infinity

            for coordinate in coordinates where input.attributor.region(at: coordinate) == .other {
                for region in input.primaryRegions {
                    guard let distance = input.attributor.distanceToBoundary(
                        of: region,
                        from: coordinate,
                    ) else {
                        continue
                    }
                    if distance < bestDistance {
                        bestDistance = distance
                        bestRegion = region
                    }
                }
            }

            if let bestRegion, bestDistance <= input.driftThresholdMeters {
                issues.append(BorderDriftIssue(
                    day: day,
                    nearestRegion: bestRegion,
                    distanceMeters: bestDistance,
                ))
            }
        }
        return issues
    }
}
