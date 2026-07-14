import AppIntents
import Foundation
import WhereCore

/// Backfill a stretch of days with the regions you were in — the Siri/Shortcuts
/// equivalent of the app's manual range entry. Additive: it unions with
/// whatever is already logged.
public struct LogTripIntent: AppIntent {
    public static let title: LocalizedStringResource = "Log a Trip"

    public static let description = IntentDescription(
        "Backfill a range of days with the regions you were in.",
    )

    @Parameter(title: "Regions")
    public var regions: [RegionEntity]

    @Parameter(title: "Start Date")
    public var startDate: Date

    @Parameter(title: "End Date")
    public var endDate: Date

    public init() {}

    public init(startDate: Date, endDate: Date, regions: [RegionEntity]) {
        self.startDate = startDate
        self.endDate = endDate
        self.regions = regions
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let regionSet = Set(regions.map(\.region))
        guard !regionSet.isEmpty else {
            return .result(dialog: IntentDialog("\(IntentStrings.chooseRegions())"))
        }
        let services = try await IntentServices.shared.current()
        let dayCount = try await WhereIntentWriter(services: services)
            .logTrip(from: startDate, through: endDate, regions: regionSet)
        guard dayCount > 0 else {
            return .result(dialog: IntentDialog("\(IntentStrings.emptyTripRange())"))
        }
        return .result(
            dialog: IntentDialog(
                "\(IntentStrings.loggedTrip(dayCount: dayCount, regions: orderedRegions(regionSet)))",
            ),
        )
    }
}
