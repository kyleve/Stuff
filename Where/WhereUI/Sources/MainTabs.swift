import SwiftUI
import WhereCore

/// The adaptive logged-in shell — the launch *destination* once the runner
/// reaches `.ready`, not a launch step. Owns the scene-scoped
/// ``YearReportModel`` as `@State` and drives its store-change subscription from
/// `scenePhase` (active → subscribe + pull, background → cancel — closing the
/// headless-relaunch rescan leak).
///
/// Phones keep the three-tab interface while iPad and Mac Catalyst use the same
/// three sections in a two-column split view. The sections receive the report by
/// explicit init injection (compile-checked wiring); the always-on
/// `WhereSession` coordinator stays in the environment.
struct MainTabs: View {
    @State private var report: YearReportModel
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
        MainView(report: report, interfaceStyle: .current)
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

#if DEBUG
    private struct MainTabsPreview: View {
        private let model = PreviewSupport.loadedModel()
        private let session = PreviewSupport.loadedSession()

        var body: some View {
            MainTabs(
                session: session,
                initialReport: PreviewSupport.sampleReport(),
                selectedYear: PreviewSupport.year,
            )
            .environment(model)
            .environment(session)
            .whereBroadwayRoot()
        }
    }

    #Preview {
        MainTabsPreview()
    }
#endif
