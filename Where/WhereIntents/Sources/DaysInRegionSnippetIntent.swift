import AppIntents
import SwiftUI
import WhereCore
import WhereUI

/// The interactive snippet behind `DaysInRegionIntent`: a day-count card with a
/// "Log today here" button. Tapping the button runs `LogDayIntent`, after which
/// the system re-runs this intent's `perform()` (a snippet reload), so the count
/// updates in place. `perform()` therefore only *reads* — the mutation lives in
/// the button's `LogDayIntent`.
public struct DaysInRegionSnippetIntent: SnippetIntent {
    public static let title: LocalizedStringResource = "Days in a Region"

    @Parameter(title: "Region")
    public var region: RegionEntity

    @Parameter(title: "Year")
    public var year: Int?

    public init() {}

    public init(region: RegionEntity, year: Int?) {
        self.region = region
        self.year = year
    }

    @MainActor
    public func perform() async throws -> some IntentResult & ShowsSnippetView {
        let services = try await IntentServices.shared.current()
        let resolvedYear = year ?? Calendar.whereIntents.component(.year, from: Date())
        let count = try await WhereIntentReader(services: services)
            .dayCount(in: region.region, year: resolvedYear)
        let snapshot = DaysInRegionSnapshot(
            region: region.region,
            year: resolvedYear,
            dayCount: count,
        )
        // "Log today here" logs into the *current* year, so it can only change
        // this card's count when the card is showing the current year. Omit it
        // otherwise, rather than offer a button that appears to do nothing.
        return .result(
            view: DaysInRegionInteractiveSnippet(
                snapshot: snapshot,
                region: region,
                canLogToday: isCurrentYear(resolvedYear),
            ),
        )
    }
}

/// The card the snippet renders: the WhereUI day-count card plus — for the
/// current year — a `Button(intent:)` that logs today for the region. The
/// interactive wrapper lives here (not WhereUI) because it references
/// `LogDayIntent`; the card body stays a plain WhereUI view.
struct DaysInRegionInteractiveSnippet: View {
    let snapshot: DaysInRegionSnapshot
    let region: RegionEntity
    let canLogToday: Bool

    var body: some View {
        content
            .whereBroadwayRoot()
    }

    @ViewBuilder private var content: some View {
        if canLogToday {
            // WhereUI owns the card's spacing/padding (stylesheet-driven); this
            // layer only supplies the intent-backed button and its region tint.
            DaysInRegionSnippetCard(snapshot: snapshot) {
                Button(intent: LogDayIntent(regions: [region])) {
                    Label {
                        Text(IntentStrings.logTodayHere)
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(snapshot.region.style.tint)
            }
        } else {
            DaysInRegionSnippetView(snapshot: snapshot)
        }
    }
}
