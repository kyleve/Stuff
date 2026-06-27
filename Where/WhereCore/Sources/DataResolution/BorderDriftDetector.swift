import Foundation

public struct BorderDriftDetector: DataIssueDetector {
    public typealias Issue = BorderDriftIssue

    public init() {}

    public func detectIssues(in input: DataIssueInput) -> [BorderDriftIssue] {
        guard !input.primaryRegions.isEmpty else { return [] }

        var issues: [BorderDriftIssue] = []
        for day in input.report.days where day.regions == [.other] {
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
