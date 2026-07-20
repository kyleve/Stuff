import SwiftUI
import WhereCore

/// Settings drill-in for presentation choices: whether empty tabs are hidden and
/// which alternate app icon is used (the icon picker pushes on from here).
struct AppearanceSettingsView: View {
    let report: YearReportModel
    var focus: SettingsFocus?

    @State private var showAppIcon = false

    var body: some View {
        @Bindable var report = report
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    Toggle(isOn: $report.hideEmptyTabs) {
                        Label(
                            Strings.settingsTabsToggle,
                            systemImage: "rectangle.bottomthird.inset.filled",
                        )
                    }
                    .settingsRow(Item.hideEmptyTabs)
                } header: {
                    Text(Strings.settingsTabsHeader)
                } footer: {
                    Text(Strings.settingsTabsFooter)
                }

                Section {
                    // A sheet (not a push) so the icon picker's Done/commit point
                    // is explicit, matching the app's other editor flows.
                    Button {
                        showAppIcon = true
                    } label: {
                        Label(Strings.settingsAppIconLink, systemImage: "app.badge")
                    }
                    .tint(.primary)
                    .settingsRow(Item.appIcon)
                } footer: {
                    Text(Strings.settingsAppIconFooter)
                }
            }
        }
        .navigationTitle(Strings.settingsAppearanceGroup)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAppIcon) {
            AppIconView()
        }
    }
}

extension AppearanceSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .appearance
    }

    enum Item: SettingsItem {
        case hideEmptyTabs
        case appIcon

        var title: String {
            switch self {
                case .hideEmptyTabs: Strings.settingsTabsToggle
                case .appIcon: Strings.settingsAppIconLink
            }
        }

        var keywords: [String] {
            switch self {
                case .hideEmptyTabs: splitKeywords(Strings.settingsKeywordsHideTabs)
                case .appIcon: splitKeywords(Strings.settingsKeywordsAppIcon)
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            AppearanceSettingsView(report: PreviewSupport.loadedYearReportModel())
        }
        .whereBroadwayRoot()
    }
#endif
