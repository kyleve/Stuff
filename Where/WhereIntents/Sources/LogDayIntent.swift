import AppIntents
import Foundation
import WhereCore

/// "Log that I was in New York today." — additively records the regions for a
/// day (defaulting to today) through `DayJournal`, then confirms.
public struct LogDayIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log a Day's Regions"

    public static let description = IntentDescription(
        "Record which regions you were in on a day.",
    )

    @Parameter(title: "Regions")
    public var regions: [RegionEntity]

    /// The day to log. Optional so "log New York today" defaults to today
    /// without Siri prompting for a date.
    @Parameter(title: "Day")
    public var date: Date?

    /// The app-registered services handoff (see `IntentServices`); resolved by
    /// the App Intents dependency container, never a singleton of ours.
    @Dependency private var intentServices: IntentServices

    public init() {}

    public init(date: Date? = nil, regions: [RegionEntity]) {
        self.date = date
        self.regions = regions
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let regionSet = Set(regions.map(\.region))
        guard !regionSet.isEmpty else {
            return .result(dialog: IntentDialog("\(IntentStrings.chooseRegions())"))
        }
        let services = try await intentServices.current()
        let day = date ?? Date()
        try await measureIntent(.logDay) {
            try await WhereIntentWriter(services: services).logDay(date: day, regions: regionSet)
        }
        return .result(
            dialog: IntentDialog(
                "\(IntentStrings.loggedDay(date: day, regions: orderedRegions(regionSet)))",
            ),
        )
    }
}
