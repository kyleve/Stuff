import SFSafeSymbols
import SnapshotKit
import SwiftUI
import WhereCore

/// Settings drill-in for presentation choices: theme, Locations-card overlays
/// and welcomes, and alternate app icon.
struct AppearanceSettingsView: View {
    let report: YearReportModel
    var focus: SettingsFocus?

    @State private var showAppIcon = false
    @Environment(WhereModel.self) private var model
    @State private var estimatedTimeSettings: EstimatedTimeAndPlanningSettingsModel
    #if DEBUG
        @Environment(\.cardDesignerModel) private var cardDesignerModel
    #endif

    init(report: YearReportModel, focus: SettingsFocus? = nil) {
        self.report = report
        self.focus = focus
        _estimatedTimeSettings = State(initialValue: EstimatedTimeAndPlanningSettingsModel(
            report: report,
        ))
    }

    var body: some View {
        @Bindable var report = report
        @Bindable var estimatedTimeSettings = estimatedTimeSettings
        SettingsFocusScope(focus: focus) {
            Form {
                Section {
                    WhereThemePicker(selection: model.theme) {
                        model.selectTheme($0)
                    }
                    .settingsRow(Item.theme)
                } header: {
                    Text(.settingsAppearanceThemeHeader)
                } footer: {
                    Text(.settingsAppearanceThemeFooter)
                }

                Section {
                    Toggle(isOn: $report.showsRecordedLocationDots) {
                        Label(
                            String(localized: .settingsAppearanceLocationDotsToggle),
                            systemSymbol: .mappinAndEllipse,
                        )
                    }
                    .settingsRow(Item.locationDots)
                } footer: {
                    Text(String(localized: .settingsAppearanceLocationDotsFooter))
                }

                Section {
                    Toggle(isOn: $report.showsLocationWelcome) {
                        Label(
                            String(localized: .settingsAppearanceLocationWelcomeToggle),
                            systemSymbol: .sparkles,
                        )
                    }
                    .settingsRow(Item.locationWelcome)

                    #if DEBUG
                        Button(action: report.resetLocationWelcome) {
                            Label(
                                String(localized: .settingsAppearanceLocationWelcomeResetTitle),
                                systemSymbol: .arrowCounterclockwise,
                            )
                        }
                        .disabled(!report.showsLocationWelcome)
                        .settingsRow(Item.resetLocationWelcome)
                    #endif
                } footer: {
                    VStack(alignment: .leading) {
                        Text(String(localized: .settingsAppearanceLocationWelcomeFooter))
                        #if DEBUG
                            Text(String(localized: .settingsAppearanceLocationWelcomeResetFooter))
                        #endif
                    }
                }

                Section {
                    Toggle(isOn: $estimatedTimeSettings.isEnabled) {
                        HStack {
                            Label(
                                String(localized: .settingsAppearanceLocationForecastsToggle),
                                systemSymbol: .chartLineUptrendXyaxis,
                            )
                            if estimatedTimeSettings.isUpdating {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }
                    }
                    .disabled(estimatedTimeSettings.isUpdating)
                    .settingsRow(Item.locationForecasts)
                } footer: {
                    Text(String(localized: .settingsAppearanceLocationForecastsFooter))
                }

                Section {
                    // A sheet (not a push) so the icon picker's Done/commit point
                    // is explicit, matching the app's other editor flows.
                    Button {
                        showAppIcon = true
                    } label: {
                        Label(String(localized: .settingsAppIconLink), systemSymbol: .appBadge)
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
                                    systemSymbol: .paintpalette,
                                )
                            }
                            .settingsRow(Item.cardDesigner)

                            NavigationLink {
                                RankingAnimationLabView()
                            } label: {
                                Label(
                                    String(localized: .rankingAnimationTitle),
                                    systemSymbol: .arrowUpArrowDown,
                                )
                            }
                            .settingsRow(Item.rankingAnimation)
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
            AppIconView()
        }
        .alert(
            String(localized: .settingsAppearanceLocationForecastsDisableErrorTitle),
            isPresented: $estimatedTimeSettings.isShowingError,
            presenting: estimatedTimeSettings.presentedFailure,
        ) { _ in
            Button(String(localized: .commonOk), role: .cancel) {}
        } message: { message in
            Text(message)
        }
    }
}

extension AppearanceSettingsView: SettingsSection {
    static var destination: SettingsDestination {
        .appearance
    }

    enum Item: SettingsItem {
        case theme
        case locationDots
        case locationWelcome
        case locationForecasts
        case appIcon
        #if DEBUG
            case resetLocationWelcome
            case cardDesigner
            case rankingAnimation
        #endif

        var title: String {
            switch self {
                case .theme: String(localized: .settingsAppearanceThemeHeader)
                case .locationDots:
                    String(localized: .settingsAppearanceLocationDotsToggle)
                case .locationWelcome:
                    String(localized: .settingsAppearanceLocationWelcomeToggle)
                case .locationForecasts:
                    String(localized: .settingsAppearanceLocationForecastsToggle)
                case .appIcon: String(localized: .settingsAppIconLink)
                #if DEBUG
                    case .resetLocationWelcome:
                        String(localized: .settingsAppearanceLocationWelcomeResetTitle)
                    case .cardDesigner: String(localized: .cardDesignerTitle)
                    case .rankingAnimation: String(localized: .rankingAnimationTitle)
                #endif
            }
        }

        var keywords: [String] {
            switch self {
                case .theme:
                    splitKeywords(String(localized: .settingsKeywordsTheme))
                case .locationDots:
                    splitKeywords(String(localized: .settingsKeywordsLocationDots))
                case .locationWelcome:
                    splitKeywords(String(localized: .settingsKeywordsLocationWelcome))
                case .locationForecasts:
                    splitKeywords(String(localized: .settingsKeywordsLocationForecasts))
                case .appIcon: splitKeywords(String(localized: .settingsKeywordsAppIcon))
                #if DEBUG
                    case .resetLocationWelcome:
                        splitKeywords(String(localized: .settingsKeywordsLocationWelcome))
                    case .cardDesigner:
                        splitKeywords(String(localized: .cardDesignerSettingsKeywords))
                    case .rankingAnimation:
                        splitKeywords(String(localized: .rankingAnimationSettingsKeywords))
                #endif
            }
        }
    }
}

#if DEBUG
    extension AppearanceSettingsView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                NavigationStack {
                    AppearanceSettingsView(report: PreviewSupport.loadedYearReportModel())
                }
                .environment(PreviewSupport.loadedModel())
                .environment(
                    \.cardDesignerModel,
                    CardDesignerModel(configuration: .standard),
                )
            }
        }
    }

    #Preview {
        AppearanceSettingsView.snapshotPreviews
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
                .push(to: RankingAnimationLabView.flyoverID),
            ],
        ) { world in
            AppearanceSettingsView(report: world.report)
        }
    }
#endif
