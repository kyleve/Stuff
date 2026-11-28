import InstallerKit
import SnapshotKit
import SwiftUI

/// Stable integration points for a host's search anchors and section highlighting.
public enum AppUpdatesSection: Hashable {
    case check
    case changes
}

/// Shared native update page. The host owns the model, app identity, and navigation eligibility.
public struct AppUpdatesView<SectionDecoration: ViewModifier>: View {
    private let model: UpdateModel
    private let branding: AppUpdateBranding
    private let sectionDecoration: (AppUpdatesSection) -> SectionDecoration

    public init(
        model: UpdateModel,
        branding: AppUpdateBranding,
        sectionDecoration: @escaping (AppUpdatesSection) -> SectionDecoration,
    ) {
        self.model = model
        self.branding = branding
        self.sectionDecoration = sectionDecoration
    }

    public var body: some View {
        UpdatePage(model: model, branding: branding, sectionDecoration: sectionDecoration)
            .installerBroadwayRoot()
            .navigationTitle(String(localized: .installerTitle))
            .navigationBarTitleDisplayMode(.inline)
    }
}

extension AppUpdatesView where SectionDecoration == EmptyModifier {
    public init(model: UpdateModel, branding: AppUpdateBranding) {
        self.init(model: model, branding: branding, sectionDecoration: { _ in EmptyModifier() })
    }
}

#if DEBUG
    extension AppUpdatesView: SnapshotProviding where SectionDecoration == EmptyModifier {
        public static var snapshots: [SnapshotCase] {
            for scenario in InstallerPreview.Scenario.allCases {
                let model = InstallerPreview.model(scenario)
                SnapshotCase(
                    name: scenario.rawValue,
                    configurations: scenario == .available || scenario == .local ?
                        .fullContentScreenRepresentative :
                        .fullContentPhoneLightDark,
                    measurementReadiness: scenario.requiresRefresh ? .sameAsCapture : .immediate,
                    onReadyToMeasure: {
                        if scenario.requiresRefresh {
                            await model.refresh(force: true)
                        }
                    },
                ) {
                    NavigationStack { AppUpdatesView(
                        model: model,
                        branding: InstallerPreview.branding,
                    ) }
                }
            }
        }
    }

    #Preview { AppUpdatesView<EmptyModifier>.snapshotPreviews }
#endif
