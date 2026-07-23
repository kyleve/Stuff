import SwiftUI
import WhereCore

/// Settings drill-in for presentation choices: which alternate app icon is used
/// (the icon picker pushes on from here).
struct AppearanceSettingsView: View {
    var focus: SettingsFocus?

    @State private var showAppIcon = false

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
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
        case appIcon

        var title: String {
            switch self {
                case .appIcon: Strings.settingsAppIconLink
            }
        }

        var keywords: [String] {
            switch self {
                case .appIcon: splitKeywords(Strings.settingsKeywordsAppIcon)
            }
        }
    }
}

#if DEBUG
    #Preview {
        NavigationStack {
            AppearanceSettingsView()
        }
        .whereBroadwayRoot()
    }
#endif
