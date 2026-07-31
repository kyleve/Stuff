import SwiftUI

/// The regular-device logged-in interface. The split view remains the root as
/// an iPad or Catalyst window resizes, letting the system collapse its columns
/// without replacing the navigation model.
struct MainSplitView: View {
    let report: YearReportModel

    @State private var selection: MainSection? = .locations

    var body: some View {
        NavigationSplitView {
            List(MainSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
        } detail: {
            // A page-style TabView keeps every section's NavigationStack and
            // local presentation state alive while the sidebar changes the
            // visible section. Its own tab chrome is intentionally hidden.
            TabView(selection: $selection) {
                Tab(value: MainSection?.some(.locations)) {
                    LocationsView(report: report)
                }

                Tab(value: MainSection?.some(.year)) {
                    YearView(report: report)
                }

                Tab(value: MainSection?.some(.settings)) {
                    SettingsView(report: report)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
        }
        .navigationSplitViewStyle(.balanced)
    }
}

#if DEBUG
    #Preview {
        MainSplitView(report: PreviewSupport.loadedYearReportModel())
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
            .whereBroadwayRoot()
    }
#endif
