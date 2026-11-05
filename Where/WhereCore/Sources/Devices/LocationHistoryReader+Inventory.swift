import Foundation

extension LocationHistoryReader {
    /// Discover logical GPS years before report selection. Even an excluded rival can carry an
    /// unresolved concern. Removed observations follow the same cutoff as ordinary history reads.
    func historyYears(calendar: Calendar) async throws -> Set<Int> {
        try await store.readSnapshot {
            let major = try await admittedMajor()
            let samples = try await RecordingDeviceRemovalFilter.visibleSamples(
                store.allSamples(),
                removals: store.recordingDeviceRemovals(),
            )
            var inventory = HistoryYearInventory()
            if major == 0 {
                for sample in samples {
                    try Task.checkCancellation()
                    try inventory.include(timestamp: sample.timestamp, calendar: calendar)
                }
                return inventory.years
            }
            guard major == RecordingEvidencePolicy.version.major else {
                throw RecordingHistorySelection.ValidationError.unsupportedPolicy
            }
            let controls = try await RecordingControlStore(store: store, policy: policy).snapshot()
            for sample in samples {
                try Task.checkCancellation()
                guard sample.source.isGPS else {
                    try inventory.include(timestamp: sample.timestamp, calendar: calendar)
                    continue
                }
                switch try RecordingCalendarResolver.assignment(
                    for: sample,
                    decisions: controls.calendarContexts,
                    version: policy.current,
                ) {
                    case let .resolved(context): try inventory.include(day: context.day)
                    case .unresolved: try inventory.includePossibleYears(at: sample.timestamp)
                }
            }
            // Source choices and opaque controls can require review without any GPS. Ordinary
            // eligibility, place, and calendar hints affect history only where observations exist.
            for choice in controls.sourceChoices {
                switch choice.scope {
                    case .fixedPeriods:
                        for period in choice
                            .periods
                        {
                            try inventory.includePossibleYears(in: period)
                        }
                    case let .recordingDay(_, day): try inventory.include(day: day)
                }
            }
            // A missing causal predecessor can hide a different declared date. Include all
            // possible years of its unresolved period, even if the received choice names a day.
            for period in RecordingPeriod.union(controls.sourceChoices.flatMap(\.periods)) {
                for segment in try HistoryDecisionResolver.resolve(
                    controls.sourceChoices,
                    within: period,
                    version: policy.current,
                ) {
                    switch segment.resolution {
                        case .incomplete: try inventory.includePossibleYears(in: segment.period)
                        case .automatic, .selected, .conflict: break
                    }
                }
            }
            for record in controls.requiresReview {
                switch record.scope {
                    // This scope applies to all discovered years; it supplies no additional date.
                    case .entireHistory: break
                    case let .periods(periods):
                        for period in periods {
                            try inventory.includePossibleYears(in: period)
                        }
                    case let .intervals(intervals):
                        for interval in intervals {
                            if let end = interval.end {
                                try inventory.includePossibleYears(in: .init(
                                    start: interval.start,
                                    end: end,
                                ))
                            } else {
                                // Keep a dated entry point for the unknown control. Like an
                                // entire-history scope, its ongoing tail applies to other
                                // discovered years without inventing years of future history.
                                try inventory.includePossibleYears(at: interval.start)
                            }
                        }
                }
            }
            return inventory.years
        }
    }
}
