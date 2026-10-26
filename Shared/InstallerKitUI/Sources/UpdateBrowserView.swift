import InstallerKit
import SnapshotKit
import SwiftUI

/// A separate navigation stack keeps manual build browsing inside the installer's sheet.
struct UpdateBrowserView: View {
    enum Route: Hashable {
        case build(UpdateBuildBrowser.Selection)
        case history(InstalledBuild.Channel)

        @MainActor @ViewBuilder
        func destination(model: UpdateModel, branding: AppUpdateBranding) -> some View {
            switch self {
                case let .build(selection):
                    UpdateBuildView(model: model, branding: branding, selection: selection)
                case let .history(channel):
                    UpdateHistoryView(model: model, channel: channel)
            }
        }
    }

    let model: UpdateModel
    let branding: AppUpdateBranding
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            UpdateChannelsView(model: model)
                .updateBrowserDestinations(model: model, branding: branding)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(String(localized: .installerDone)) { dismiss() }
                    }
                }
        }
        .installerBroadwayRoot()
    }
}

extension View {
    func updateBrowserDestinations(model: UpdateModel, branding: AppUpdateBranding) -> some View {
        navigationDestination(for: UpdateBrowserView.Route.self) { route in
            route.destination(model: model, branding: branding)
        }
    }
}

#if DEBUG
    extension UpdateBrowserView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            for scenario in InstallerBrowserPreview.Scenario.allCases {
                let model = InstallerBrowserPreview.model(scenario)
                SnapshotCase(
                    name: scenario.rawValue,
                    configurations: scenario == .available ? .fullContentScreenRepresentative :
                        .fullContentPhoneLightDark,
                    measurementReadiness: scenario.requiresRefresh ? .sameAsCapture : .immediate,
                    onReadyToMeasure: {
                        if scenario.requiresRefresh { await model.refresh(force: true) }
                    },
                ) {
                    UpdateBrowserView(model: model, branding: InstallerPreview.branding)
                }
            }
        }
    }

    #Preview { UpdateBrowserView.snapshotPreviews }
#endif
