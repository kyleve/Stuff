import AppIntents
import Foundation
import WhereCore

/// "How many days was I in California this year?" — reads the year report's
/// per-region day count and returns it as both a value (for Shortcuts) and a
/// spoken dialog.
public struct DaysInRegionIntent: AppIntent {
    public static let title: LocalizedStringResource = "Count Days in a Region"

    public static let description = IntentDescription(
        "Find out how many days you've spent in a region so far this year.",
    )

    @Parameter(title: "Region")
    public var region: RegionEntity

    /// The calendar year to count. Optional so a bare "days in California"
    /// defaults to the current year without Siri prompting for one.
    @Parameter(title: "Year")
    public var year: Int?

    public init() {}

    public init(region: RegionEntity, year: Int? = nil) {
        self.region = region
        self.year = year
    }

    public func perform() async throws -> some IntentResult & ReturnsValue<Int> & ProvidesDialog {
        let services = try await IntentServices.shared.current()
        let resolvedYear = year ?? Calendar.whereIntents.component(.year, from: Date())
        let count = try await WhereIntentReader(services: services)
            .dayCount(in: region.region, year: resolvedYear)
        // The value + dialog answer voice-only Siri; the interactive snippet
        // renders the card and its "Log today here" button on screen.
        return .result(
            value: count,
            dialog: IntentDialog(
                "\(IntentStrings.daysInRegion(region: region.region, days: count, year: resolvedYear))",
            ),
            snippetIntent: DaysInRegionSnippetIntent(region: region, year: resolvedYear),
        )
    }
}
