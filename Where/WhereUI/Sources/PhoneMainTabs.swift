import SwiftUI

/// The compact-width logged-in interface, preserving Where's three fixed
/// iPhone tabs.
struct PhoneMainTabs: View {
    let report: YearReportModel

    @State private var selection = MainSection.locations

    var body: some View {
        TabView(selection: $selection) {
            Tab(
                MainSection.locations.title,
                systemImage: MainSection.locations.systemImage,
                value: MainSection.locations,
            ) {
                LocationsView(report: report)
                    .reportingDeveloperTabBarInset()
            }

            Tab(
                MainSection.year.title,
                systemImage: MainSection.year.systemImage,
                value: MainSection.year,
            ) {
                YearView(report: report)
                    .reportingDeveloperTabBarInset()
            }

            Tab(
                MainSection.settings.title,
                systemImage: MainSection.settings.systemImage,
                value: MainSection.settings,
            ) {
                SettingsView(report: report)
                    .reportingDeveloperTabBarInset()
            }
        }
        // Keep the tab bar fixed — don't minimize it as content scrolls.
        .tabBarMinimizeBehavior(.never)
    }
}

#if DEBUG
    #Preview {
        PhoneMainTabs(report: PreviewSupport.loadedYearReportModel())
            .environment(PreviewSupport.loadedModel())
            .environment(PreviewSupport.loadedSession())
            .whereBroadwayRoot()
    }
#endif
