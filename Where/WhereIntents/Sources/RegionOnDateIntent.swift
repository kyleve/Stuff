import AppIntents
import Foundation
import RegionKit
import SwiftUI
import WhereCore
import WhereUI

/// "What region was I in on June 3?" — the regions a given calendar day counts
/// for, as a spoken dialog plus a snippet card.
public struct RegionOnDateIntent: AppIntent {
    public static let title: LocalizedStringResource = "Find Regions on a Date"

    public static let description = IntentDescription(
        "Look up which regions a particular day counted for.",
    )

    @Parameter(title: "Date")
    public var date: Date

    public init() {}

    public init(date: Date) {
        self.date = date
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let services = try WhereServices.forIntents()
        let regions = try await WhereIntentReader(services: services).regions(on: date)
        let ordered = orderedRegions(regions)
        return .result(
            dialog: IntentDialog("\(IntentStrings.regionsOnDate(date, regions: ordered))"),
            view: RegionsSnippetView.onDate(date, regions: ordered).whereBroadwayRoot(),
        )
    }
}

/// The regions in `Region.allCases` declaration order, so multi-region output
/// (entities and dialog) is stable.
func orderedRegions(_ regions: Set<Region>) -> [Region] {
    Region.allCases.filter(regions.contains)
}
