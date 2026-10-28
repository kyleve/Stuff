import Foundation
import RegionKit

/// The read-only catalog enrichment seam used by the scene's Elsewhere model.
public protocol ElsewhereResolving: Sendable {
    func resolve(_ input: ElsewhereInput) async throws -> ElsewhereReport
}

/// Resolves only automatically attributed Other observations. Geometry is loaded
/// lazily on this actor, outside the ingestion path and the main actor.
public actor ElsewhereResolver: ElsewhereResolving {
    private var catalog: (any RegionAttributing)?
    private static let logger = WhereLog.reporting(ElsewhereResolverLog.self)

    public init() {}

    @_spi(Testing)
    public init(catalog: any RegionAttributing) {
        self.catalog = catalog
    }

    public func resolve(_ input: ElsewhereInput) async throws -> ElsewhereReport {
        try Self.logger.measure(.resolve, budget: .seconds(1)) {
            try resolveSnapshot(input)
        }
    }

    private func resolveSnapshot(_ input: ElsewhereInput) throws -> ElsewhereReport {
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
            let day = CalendarDay(from: entry.sample.timestamp, in: input.calendar)
            guard originalDays[day] != nil else { continue }
            var regions = entry.regions
            if let asserted = authoritative[day] {
                // Whole-day assertions win; GPS can illustrate only their exact regions.
                regions.formIntersection(asserted)
            } else if regions.contains(.other),
                      !(entry.sample.source.isGPS && revisions[entry.sample.id]?
                          .replacementRegions != nil)
            {
                let named = catalogRegion(at: entry.sample.coordinate)
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
                resolvedHistory.append(AttributedLocationSample(
                    sample: entry.sample,
                    regions: regions,
                ))
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
        return ElsewhereReport(year: input.report.year, regions: regions)
    }

    private func catalogRegion(at coordinate: Coordinate) -> Region {
        if let catalog { return catalog.region(at: coordinate) }
        let loaded = Self.logger.measure(.loadCatalog, budget: .seconds(1)) {
            RegionAttributor(for: RegionCatalog.shared.all)
        }
        catalog = loaded
        return loaded.region(at: coordinate)
    }
}
