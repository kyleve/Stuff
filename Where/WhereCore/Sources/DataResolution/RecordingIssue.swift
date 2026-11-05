import Foundation

/// One continuous recording concern. Its segments retain the original problems and evidence;
/// grouping changes presentation granularity without assigning unknown dates or bridging gaps.
public struct RecordingIssue: Hashable, Sendable, Identifiable {
    /// A derived presentation identity. A review queue must retain its original scope separately,
    /// because reassessment can split, merge, or move this boundary.
    public struct ID: Hashable, Codable, Sendable {
        public let period: RecordingPeriod
    }

    public let period: RecordingPeriod
    public let segments: Set<RecordingHistorySelection.Issue>
    public let policyVersion: DataSemanticsVersion

    public var id: ID {
        ID(period: period)
    }

    public var days: RecordingHistorySelection.Days {
        let known = Set(segments.flatMap(\.days.candidates))
        let unassigned = segments.contains {
            switch $0.days {
                case .known: false
                case .unassigned: true
            }
        }
        return unassigned ? .unassigned(known: known) : .known(known)
    }

    public var sampleIDs: Set<UUID> {
        Set(segments.flatMap(\.sampleIDs))
    }

    public static func grouped(
        _ issues: [RecordingHistorySelection.Issue],
        version: DataSemanticsVersion,
    ) throws -> [Self] {
        for issue in issues {
            try issue.period.validate()
        }
        let ordered = Set(issues).sorted { $0.period < $1.period }
        var result: [Self] = []
        var index = ordered.startIndex
        while index < ordered.endIndex {
            let start = ordered[index].period.start
            var end = ordered[index].period.end
            var segments: Set<RecordingHistorySelection.Issue> = []
            repeat {
                let issue = ordered[index]
                end = max(end, issue.period.end)
                segments.insert(issue)
                index += 1
            } while index < ordered.endIndex && ordered[index].period.start <= end
            try result.append(Self(
                period: RecordingPeriod(start: start, end: end),
                segments: segments,
                policyVersion: version,
            ))
        }
        return result
    }
}
