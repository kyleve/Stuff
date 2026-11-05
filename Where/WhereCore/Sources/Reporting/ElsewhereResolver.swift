import Foundation
import RegionKit

/// The read-only catalog enrichment seam used by the scene's Elsewhere model.
public protocol ElsewhereResolving: Sendable {
    func resolve(_ input: ElsewhereInput) async throws -> ElsewhereReport
}

/// Resolves only automatically attributed Other observations. Geometry is loaded
/// lazily on this actor, outside the ingestion path and the main actor.
public actor ElsewhereResolver: ElsewhereResolving {
    private let geography: HistoryRegionAttribution
    private static let logger = WhereLog.reporting(ElsewhereResolverLog.self)

    public init(geography: HistoryRegionAttribution) {
        self.geography = geography
    }

    public func resolve(_ input: ElsewhereInput) async throws -> ElsewhereReport {
        try await Self.logger.measure(.resolve, budget: .seconds(1)) {
            try await resolveSnapshot(input)
        }
    }

    private func resolveSnapshot(_ input: ElsewhereInput) async throws -> ElsewhereReport {
        try Task.checkCancellation()
        let originalDays = Dictionary(uniqueKeysWithValues: input.report.days.map { ($0.day, $0) })
        let authoritative = Dictionary(
            input.manualDays.filter(\.isAuthoritative).map { ($0.day, $0.regions) },
            uniquingKeysWith: { _, latest in latest },
        )
        var revisions: [UUID: SampleAttributionRevision] = [:]
        for revision in input.history.revisions {
            if let previous = revisions[revision.sampleID],
               !SampleAttributionRevision.newer(revision, than: previous) { continue }
            revisions[revision.sampleID] = revision
        }

        var daysByRegion: [Region: Set<CalendarDay>] = [:]
        var resolvedHistory: [AttributedLocationSample] = []
        for entry in input.history.samples {
            try Task.checkCancellation()
            let day = entry.calendarDay(in: input.calendar)
            guard originalDays[day] != nil else { continue }
            var regions = entry.regions
            let hasSpecificGPSGeography: Bool = switch input.history.contract {
                case .foundation: false
                case .recording: entry.sample.source.isGPS
            }
            if let asserted = authoritative[day] {
                // An explicit unknown overlay keeps non-primary points as illustrations of
                // Other. The full catalog must not rename that user assertion.
                if hasSpecificGPSGeography, asserted.contains(.other),
                   revisions[entry.sample.id]?.replacementRegions == nil,
                   !regions.subtracting(input.primaryRegions).isEmpty
                {
                    regions.insert(.other)
                }
                regions.formIntersection(asserted)
            } else if !hasSpecificGPSGeography, regions.contains(.other),
                      !(entry.sample.source.isGPS && revisions[entry.sample.id]?
                          .replacementRegions != nil)
            {
                let named = await geography.snapshot().region(at: entry.sample.coordinate)
                // Never turn enrichment into a new primary credit.
                if !input.primaryRegions.contains(named) {
                    regions.remove(.other)
                    regions.insert(named)
                }
            }
            regions.subtract(input.primaryRegions)
            for region in regions {
                daysByRegion[region, default: []].insert(day)
            }
            if !regions.isEmpty {
                resolvedHistory.append(entry.replacingRegions(regions))
            }
        }

        // Manual Other is an explicit unknown, even alongside named GPS visits.
        for day in input.manualDays where originalDays[day.day] != nil {
            let regions = authoritative[day.day] ?? day.regions
            for region in regions.subtracting(input.primaryRegions) {
                daysByRegion[region, default: []].insert(day.day)
            }
        }

        let aggregator = DayAggregator(calendar: input.calendar, timeZone: input.calendar.timeZone)
        let locations = aggregator.locations(in: Set(daysByRegion.keys), history: resolvedHistory)
        let representatives = aggregator.representativeCoordinates(history: resolvedHistory)
        let regions = Region.inCanonicalOrder(daysByRegion.keys).map { region in
            ElsewhereRegion(
                region: region,
                days: (daysByRegion[region] ?? []).sorted().compactMap { originalDays[$0] },
                locations: locations[region] ?? [],
                // Other may be an explicit assertion. Keep its recorded map points,
                // but do not infer a more specific teaser from those coordinates.
                representativeCoordinate: region == .other ? nil : representatives[region],
            )
        }
        try Task.checkCancellation()
        return ElsewhereReport(
            year: input.report.year,
            regions: regions,
            completeness: input.report.completeness,
        )
    }
}
