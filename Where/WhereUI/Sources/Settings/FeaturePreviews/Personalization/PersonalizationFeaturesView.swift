import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// A feature-marketing gallery for the region appearance and alternate app-icon
/// systems, with links into their existing editors.
struct PersonalizationFeaturesView: View {
    let report: YearReportModel
    let focus: SettingsFocus?

    @State private var iconModel: AppIconModel
    @State private var presentedSheet: Sheet?

    @MainActor
    init(
        report: YearReportModel,
        focus: SettingsFocus?,
        primaryAppIconName: String,
        iconModel: AppIconModel? = nil,
    ) {
        self.report = report
        self.focus = focus
        _iconModel = State(initialValue: iconModel ?? AppIconModel(
            primaryAppIconName: primaryAppIconName,
        ))
    }

    var body: some View {
        StaggeredRevealScope {
            SettingsFocusScope(focus: focus) {
                PersonalizationFeaturesContent(
                    report: report,
                    iconModel: iconModel,
                    showRegions: showRegions,
                    showAppIcons: showAppIcons,
                )
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
                case .regions: RegionsSettingsView(usedThisYear: regionsUsedThisYear)
                case .appIcon: AppIconView(model: iconModel)
            }
        }
    }

    private var regionsUsedThisYear: Set<Region> {
        guard let totals = report.report?.totals else { return [] }
        return Set(totals.filter { $0.key != .other && $0.value > 0 }.map(\.key))
    }

    private func showRegions() {
        presentedSheet = .regions
    }

    private func showAppIcons() {
        presentedSheet = .appIcon
    }

    private enum Sheet: Hashable, Identifiable {
        case regions
        case appIcon

        var id: Self {
            self
        }
    }
}

extension PersonalizationFeaturesView: SettingsSection {
    static var destination: SettingsDestination {
        .personalization
    }

    enum Item: SettingsItem {
        case regions
        case appIcon
        case appearance

        var title: String {
            switch self {
                case .regions: String(localized: .settingsExplorePersonalizationRegionsTitle)
                case .appIcon: String(localized: .settingsExplorePersonalizationIconTitle)
                case .appearance: String(localized: .settingsExplorePersonalizationAppearanceTitle)
            }
        }

        var keywords: [String] {
            splitKeywords(String(localized: .settingsKeywordsPersonalizationFeatures))
        }
    }
}

#if DEBUG
    extension PersonalizationFeaturesView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Default",
                configurations: .fullContentScreenDefaults,
                measurementReadiness: .immediate,
            ) {
                PersonalizationFeaturesView(
                    report: PreviewSupport.loadedYearReportModel(),
                    focus: nil,
                    primaryAppIconName: "AppIcon",
                    iconModel: .preview(activeAlternateIconName: "AppIconPride"),
                )
            }
        }
    }

    #Preview {
        NavigationStack { PersonalizationFeaturesView.snapshotPreviews }
            .whereBroadwayRoot(regionStyles: RegionStyleResolver(appearances: [
                .california: RegionAppearanceCatalog.defaultAppearance(for: .california),
            ]))
    }
#endif

#if DEBUG
    extension PersonalizationFeaturesView: WhereFlyoverProviding {
        static let flyoverData = WhereFlyoverData.snapshots(
            PersonalizationFeaturesView.self,
            title: "Make It Yours",
            routes: [
                .modal(to: RegionsSettingsView.flyoverID),
                .modal(to: AppIconView.flyoverID),
                .push(to: AppearanceSettingsView.flyoverID),
            ],
        )
    }
#endif
