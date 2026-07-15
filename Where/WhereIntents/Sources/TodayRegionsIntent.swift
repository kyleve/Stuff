import AppIntents
import Foundation
import SwiftUI
import WhereCore
import WhereUI

/// "Where am I today?" — the regions today already counts for. Prefers the
/// app-published widget snapshot (no store read) and falls back to the year
/// report's today row.
public struct TodayRegionsIntent: AppIntent {
    public static let title: LocalizedStringResource = "Show Today's Regions"

    public static let description = IntentDescription(
        "See which regions today counts for so far.",
    )

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let services = try await IntentServices.shared.current()
        let regions = try await WhereIntentReader(services: services).todayRegions()
        let ordered = orderedRegions(regions)
        return .result(
            dialog: IntentDialog("\(IntentStrings.today(regions: ordered))"),
            view: RegionsSnippetView.today(regions: ordered).whereBroadwayRoot(),
        )
    }
}
