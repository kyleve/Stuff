import AppIntents
import Foundation
import WhereCore

/// "Where am I today?" — the regions today already counts for. Prefers the
/// app-published widget snapshot (no store read) and falls back to the year
/// report's today row.
public struct TodayRegionsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Today's Regions"

    public static let description = IntentDescription(
        "See which regions today counts for so far.",
    )

    public init() {}

    public func perform() async throws
        -> some IntentResult & ReturnsValue<[RegionEntity]> & ProvidesDialog
    {
        let services = try WhereServices.forIntents()
        let regions = try await WhereIntentReader(services: services).todayRegions()
        let ordered = orderedRegions(regions)
        return .result(
            value: ordered.map(RegionEntity.init),
            dialog: IntentDialog("\(IntentStrings.today(regions: ordered))"),
        )
    }
}
