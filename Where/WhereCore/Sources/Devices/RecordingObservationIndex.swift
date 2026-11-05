import Foundation

/// A timestamp-sorted evidence window. Equal-time observations remain together so range
/// lookup cannot hide contradictory geography or recording-day assignments.
struct RecordingObservationIndex {
    let observations: [RecordingObservation]

    init(_ observations: [RecordingObservation]) {
        self.observations = observations.sorted {
            if $0.sample.timestamp != $1.sample.timestamp {
                return $0.sample.timestamp < $1.sample.timestamp
            }
            return $0.sample.id.uuidString < $1.sample.id.uuidString
        }
    }

    func observations(in period: RecordingPeriod) -> [RecordingObservation] {
        Array(observations[lowerBound(period.start) ..< lowerBound(period.end)])
    }

    /// The evidence padding includes its far endpoint, but coverage remains half-open.
    func context(
        in coverage: RecordingPeriod,
        around period: RecordingPeriod,
        padding: TimeInterval,
    ) -> [RecordingObservation] {
        let lower = lowerBound(max(coverage.start, period.start.addingTimeInterval(-padding)))
        let lastIncluded = period.end.addingTimeInterval(padding)
        let upper = min(
            lowerBound(coverage.end),
            partitionIndex { $0.sample.timestamp <= lastIncluded },
        )
        return Array(observations[lower ..< max(lower, upper)])
    }

    private func lowerBound(_ instant: Date) -> Int {
        partitionIndex { $0.sample.timestamp < instant }
    }

    private func partitionIndex(
        before predicate: (RecordingObservation) -> Bool,
    ) -> Int {
        var lower = 0
        var upper = observations.count
        while lower < upper {
            let middle = lower + (upper - lower) / 2
            if predicate(observations[middle]) { lower = middle + 1 }
            else { upper = middle }
        }
        return lower
    }
}
