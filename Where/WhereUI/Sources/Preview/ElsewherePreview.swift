#if DEBUG
    import Foundation
    import RegionKit
    @_spi(Testing) import WhereCore

    /// Fixed place labels keep the production naming seam deterministic in captures.
    struct PreviewPlaceNamer: PlaceNaming {
        func name(for coordinate: Coordinate) async -> String? {
            if coordinate == ElsewherePreview.vegas { return "Las Vegas, United States" }
            if coordinate == ElsewherePreview.portland { return "Portland, United States" }
            return nil
        }
    }

    enum ElsewherePreview {
        static let vegas = Coordinate(latitude: 36.1699, longitude: -115.1398)
        static let portland = Coordinate(latitude: 45.5152, longitude: -122.6784)
    }

    struct FailingElsewhereResolver: ElsewhereResolving {
        func resolve(_: ElsewhereInput) async throws -> ElsewhereReport {
            throw CocoaError(.fileReadUnknown)
        }
    }

    extension PreviewSupport {
        @MainActor
        static func multiplePrimaryYearReportModel() -> YearReportModel {
            YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    primaryRegions: [.california, .newYork, .canada],
                    report: sampleReport(),
                    primaryRegionLocations: sampleYearReportDetails().primaryRegionLocations,
                ),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { referenceNow },
            )
        }

        @MainActor
        static func elsewhereCatalogYearReportModel() -> YearReportModel {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            let samples = [
                ElsewherePreview.vegas,
                ElsewherePreview.vegas,
                ElsewherePreview.portland,
                Coordinate(latitude: 49.2827, longitude: -123.1207),
            ].enumerated().map { offset, coordinate in
                AttributedLocationSample(
                    sample: LocationSample(
                        timestamp: CalendarDay(year: year, month: 6, day: offset + 1)
                            .startOfDay(in: calendar),
                        coordinate: coordinate,
                        horizontalAccuracy: 10,
                        source: .gpsVisit,
                    ),
                    regions: [.other],
                )
            }
            let manualDays = [DayPresence(
                day: CalendarDay(year: year, month: 6, day: 5),
                regions: [.other],
            )]
            let report = DayAggregator(calendar: calendar, timeZone: calendar.timeZone).report(
                for: year,
                history: samples,
                manualDays: manualDays,
            )
            return YearReportModel(
                services: previewServices(),
                details: YearReportDetails(
                    elsewhereInput: ElsewhereInput(
                        report: report,
                        primaryRegions: [.california, .newYork],
                        history: LocationHistoryProjection(samples: samples, revisions: []),
                        manualDays: manualDays,
                        calendar: calendar,
                    ),
                    primaryRegionLocations: [:],
                ),
                selectedYear: year,
                preferences: previewPreferences(),
                now: { referenceNow },
            )
        }
    }
#endif
