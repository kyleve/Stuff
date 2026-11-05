#if DEBUG
    import Foundation
    @_spi(Testing) import WhereCore

    /// Equal date ranges in different years and a failed refresh retaining the same work.
    @MainActor
    enum ResolutionPreview {
        static func historical(failed: Bool) -> ResolveModel {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = .gmt
            let scans = [2024, 2025].reduce(into: [Int: DataIssueScanResult]()) { scans, year in
                let first = CalendarDay(year: year, month: 3, day: 1)
                scans[year] = DataIssueScanResult(
                    revision: UUID(),
                    completeness: .foundation,
                    issues: [MissingDaysIssue(range: .init(
                        start: first,
                        end: first.adding(days: 4),
                        dayCount: 5,
                    ))],
                    reviews: [],
                    completedFlights: [],
                    nextReassessmentAt: nil,
                )
            }
            do {
                let history = try HistoricalDataIssueScanResult(
                    yearScans: scans,
                    calendar: calendar,
                )
                return ResolveModel(
                    services: PreviewSupport.previewServices(),
                    source: FixtureResolutionSource(state: failed
                        ? .failed(URLError(.notConnectedToInternet), previous: history)
                        : .loaded(history)),
                )
            } catch {
                preconditionFailure("Invalid historical resolution fixture: \(error)")
            }
        }
    }
#endif
