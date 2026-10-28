import AppIntents
import WhereIntents

/// The App Shortcuts Where offers to Siri, Spotlight, and the Shortcuts app.
///
/// It lives in the app target (not `WhereIntents`) so App Intents metadata
/// extraction reliably discovers the phrases from the main bundle. Every phrase
/// must contain `\(.applicationName)`; Siri collects any required parameters
/// (which region, which day) after the phrase is matched.
struct WhereShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TodayRegionsIntent(),
            phrases: [
                "Show my regions in \(.applicationName)",
                "Where am I today in \(.applicationName)",
            ],
            shortTitle: "Today's Regions",
            systemImageName: "location.fill",
        )
        AppShortcut(
            intent: DaysInRegionIntent(),
            phrases: [
                "Count my days in \(.applicationName)",
                "How many days in a region in \(.applicationName)",
            ],
            shortTitle: "Days in a Region",
            systemImageName: "calendar",
        )
        AppShortcut(
            intent: RegionOnDateIntent(),
            phrases: [
                "Look up a region in \(.applicationName)",
                "Where was I on a day in \(.applicationName)",
            ],
            shortTitle: "Region on a Date",
            systemImageName: "calendar.badge.clock",
        )
        AppShortcut(
            intent: LogDayIntent(),
            phrases: [
                "Log a day in \(.applicationName)",
                "Log where I was in \(.applicationName)",
            ],
            shortTitle: "Log a Day",
            systemImageName: "mappin.and.ellipse",
        )
    }
}
