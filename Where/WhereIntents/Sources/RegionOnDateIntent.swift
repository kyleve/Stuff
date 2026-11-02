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

    /// The app-registered services handoff (see `IntentServices`); resolved by
    /// the App Intents dependency container, never a singleton of ours.
    @Dependency private var intentServices: IntentServices

    public init() {}

    public init(date: Date) {
        self.date = date
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = try await intentServices.currentContext()
        let services = context.services
        let snippet = try await measureIntent(.regionOnDate) {
            let regions = try await WhereIntentReader(services: services).regions(on: date)
            return try await context.regionsSnippet(regions: regions)
        }
        return .result(
            dialog: IntentDialog("\(IntentStrings.regionsOnDate(date, regions: snippet.regions))"),
            view: RegionsSnippetView.onDate(date, regions: snippet.regions)
                .whereBroadwayRoot(snippet.presentation),
        )
    }
}
