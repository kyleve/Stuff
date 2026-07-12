import SwiftUI
import WhereCore

/// The logged-in tab bar — the launch *destination* once the runner reaches
/// `.ready`, not a launch step. Owns the scene-scoped ``YearReportModel`` as
/// `@State`, drives its store-change subscription from `scenePhase` (active →
/// subscribe + pull, background → cancel — closing the headless-relaunch rescan
/// leak), and renders the Resolve badge from its count.
///
/// The four tabs receive the report by explicit init injection (compile-checked
/// wiring); the always-on `WhereSession` coordinator stays in the environment.
struct MainTabs: View {
    /// Identity for the tab-bar selection. The Elsewhere and Resolve tabs are
    /// conditional (see `body`), so a stable value lets the selection survive a
    /// tab appearing/disappearing and lets `body` keep a tab mounted while the
    /// user is still on it.
    private enum TabID: Hashable {
        case primary
        case elsewhere
        case resolution
        case settings
    }

    @State private var report: YearReportModel
    @State private var selection: TabID = .primary
    @Environment(\.scenePhase) private var scenePhase

    /// Build the scene's report model from the coordinator's service layer.
    /// `initialReport` / `selectedYear` are the preview/test seam threaded from
    /// `WhereModel`; both are nil / the current year in the app.
    init(session: WhereSession, initialReport: YearReport?, selectedYear: Int) {
        _report = State(initialValue: YearReportModel(
            services: session.services,
            report: initialReport,
            selectedYear: selectedYear,
            preferences: session.preferences,
            now: session.now,
        ))
    }

    var body: some View {
        TabView(selection: $selection) {
            Tab(String(localized: .tabPrimary), systemImage: "star.fill", value: TabID.primary) {
                PrimaryView(report: report)
                    .reportingDeveloperTabBarInset()
            }

            // With "hide empty tabs" on (the default), Elsewhere and Resolve
            // appear only when they have something to show — but stay mounted
            // while they're the current selection, so resolving the last issue
            // (or emptying Elsewhere) never yanks the user off the tab they're on;
            // the tab drops out the next time they switch away. With the setting
            // off, both tabs are always present.
            if !report.hideEmptyTabs || !report.ranking.secondary.isEmpty
                || selection == .elsewhere
            {
                Tab(
                    String(localized: .tabElsewhere),
                    systemImage: "globe.americas.fill",
                    value: TabID.elsewhere,
                ) {
                    SecondaryView(report: report)
                        .reportingDeveloperTabBarInset()
                }
            }

            if !report.hideEmptyTabs || report.dataIssueCount > 0 || selection == .resolution {
                Tab(
                    String(localized: .tabResolution),
                    systemImage: "checklist",
                    value: TabID.resolution,
                ) {
                    ResolutionView(report: report)
                        .reportingDeveloperTabBarInset()
                }
                .badge(report.dataIssueCount)
            }

            Tab(
                String(localized: .tabSettings),
                systemImage: "gearshape.fill",
                value: TabID.settings,
            ) {
                SettingsView(report: report)
                    .reportingDeveloperTabBarInset()
            }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        // Subscribe + pull once the scene is on screen, and again whenever it
        // returns to the foreground; cancel the subscription on background so a
        // backgrounded scene drives no refreshes.
        .task { await report.activate() }
        .onChange(of: scenePhase) { _, newPhase in
            switch newPhase {
                case .active:
                    Task { await report.activate() }
                case .background:
                    report.deactivate()
                case .inactive:
                    break
                @unknown default:
                    break
            }
        }
    }
}
