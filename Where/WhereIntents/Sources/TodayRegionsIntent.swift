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

    /// The app-registered services handoff (see `IntentServices`); resolved by
    /// the App Intents dependency container, never a singleton of ours.
    @Dependency private var intentServices: IntentServices

    public init() {}

    @MainActor
    public func perform() async throws -> some IntentResult & ProvidesDialog & ShowsSnippetView {
        let context = try await intentServices.currentContext()
        let services = context.services
        let regions = try await measureIntent(.todayRegions) {
            try await WhereIntentReader(
                services: services,
                todaySnapshot: { [appGroupIdentifier = intentServices.appGroupIdentifier] in
                    do {
                        return try WidgetSnapshotStore.shared(
                            appGroupIdentifier: appGroupIdentifier,
                        ).read()
                    } catch {
                        WhereIntentsLog.logger(
                            attachments: [.error(error, name: "snapshot-read-error")],
                        ) {
                            .widgetSnapshotReadFailed(description: String(describing: error))
                        }
                        return nil
                    }
                },
            ).todayRegions()
        }
        let ordered = orderedRegions(regions)
        return .result(
            dialog: IntentDialog("\(IntentStrings.today(regions: ordered))"),
            view: RegionsSnippetView.today(regions: ordered)
                .whereBroadwayRoot(theme: context.theme),
        )
    }
}
