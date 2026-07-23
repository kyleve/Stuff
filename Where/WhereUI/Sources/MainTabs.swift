import SwiftUI
import WhereCore

/// The logged-in tab bar — the launch *destination* once the runner reaches
/// `.ready`, not a launch step. Owns the scene-scoped ``YearReportModel`` as
/// `@State` and drives its store-change subscription from `scenePhase` (active →
/// subscribe + pull, background → cancel — closing the headless-relaunch rescan
/// leak).
///
/// Three fixed tabs — Locations, Your Year, Settings. Elsewhere is folded into
/// Locations (an entry card) and Resolve into a Locations toolbar button; the
/// data screens (attachments, logged days, regions) live in the Settings "Data"
/// group. The tabs receive the report by explicit init injection (compile-
/// checked wiring); the always-on `WhereSession` coordinator stays in the
/// environment.
struct MainTabs: View {
    /// Identity for the tab-bar selection.
    private enum TabID: Hashable {
        case locations
        case year
        case settings
    }

    @State private var report: YearReportModel
    @State private var selection: TabID = .locations
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
            Tab(
                String(localized: .tabLocations),
                systemImage: "location.fill",
                value: TabID.locations,
            ) {
                LocationsView(report: report)
                    .reportingDeveloperTabBarInset()
            }

            Tab(String(localized: .tabYear), systemImage: "calendar", value: TabID.year) {
                YearView(report: report)
                    .reportingDeveloperTabBarInset()
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
        // Keep the tab bar fixed — don't minimize it as content scrolls.
        .tabBarMinimizeBehavior(.never)
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
