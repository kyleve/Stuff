import SwiftUI
import WhereCore

/// Settings drill-in for presentation choices: which alternate app icon is used
/// (the icon picker pushes on from here).
struct AppearanceSettingsView: View {
    @Environment(\.primaryAppIconName) private var primaryAppIconName
    var focus: SettingsFocus?

    @State private var showAppIcon = false
    #if DEBUG
        @Environment(\.cardDesignerModel) private var cardDesignerModel
    #endif

    var body: some View {
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    // A sheet (not a push) so the icon picker's Done/commit point
                    // is explicit, matching the app's other editor flows.
                    Button {
                        showAppIcon = true
                    } label: {
                        Label(String(localized: .settingsAppIconLink), systemImage: "app.badge")
                    }
                    .tint(.primary)
                    .settingsRow(Item.appIcon)
                } footer: {
                    Text(String(localized: .settingsAppIconFooter))
                }

                #if DEBUG
                    if let cardDesignerModel {
                        Section {
                            NavigationLink {
                                CardDesignerStudioView(model: cardDesignerModel)
                            } label: {
                                Label(
                                    String(localized: .cardDesignerTitle),
                                    systemImage: "paintpalette",
                                )
                            }
                            .settingsRow(Item.cardDesigner)
                        } header: {
                            Text(String(localized: .cardDesignerSettingsHeader))
                        } footer: {
                            Text(String(localized: .cardDesignerSettingsFooter))
                        }
                    }
                #endif
            }
        }
        .navigationTitle(String(localized: .settingsAppearanceGroup))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showAppIcon) {
            AppIconView(primaryAppIconName: primaryAppIconName)
        }
    }
}

extension AppearanceSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .appearance
    }

    enum Item: SettingsItem {
        case appIcon
        #if DEBUG
            case cardDesigner
        #endif

        var title: String {
            switch self {
                case .appIcon: String(localized: .settingsAppIconLink)
                #if DEBUG
                    case .cardDesigner: String(localized: .cardDesignerTitle)
                #endif
            }
        }

        var keywords: [String] {
            switch self {
                case .appIcon: splitKeywords(String(localized: .settingsKeywordsAppIcon))
                #if DEBUG
                    case .cardDesigner:
                        splitKeywords(String(localized: .cardDesignerSettingsKeywords))
                #endif
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

#if DEBUG
    extension AppearanceSettingsView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.hosted(
            AppearanceSettingsView.self,
            title: "Appearance Settings",
            routes: [
                .modal(to: AppIconView.flyoverID),
                .push(to: CardDesignerStudioView.flyoverID),
            ],
        ) { _ in
            AppearanceSettingsView()
        }
    }
#endif
