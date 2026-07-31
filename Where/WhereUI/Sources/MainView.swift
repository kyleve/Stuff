import SnapshotKit
import SwiftUI

/// Selects the device-family-appropriate presentation of the logged-in
/// sections while keeping report ownership in ``MainTabs``.
struct MainView: View {
    let report: YearReportModel
    let interfaceStyle: MainInterfaceStyle

    var body: some View {
        switch interfaceStyle {
            case .tabs:
                PhoneMainTabs(report: report)
            case .split:
                MainSplitView(report: report)
        }
    }
}

#if DEBUG
    extension MainView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            whereSnapshot(
                name: "Split",
                configurations: SnapshotConfiguration.combinations(
                    devices: [.iPad],
                    colorSchemes: [.light, .dark],
                ),
                settle: .settledAtLeast(minDuration: 1.0),
            ) {
                MainView(
                    report: PreviewSupport.loadedYearReportModel(),
                    interfaceStyle: .split,
                )
                .environment(PreviewSupport.loadedModel())
                .environment(PreviewSupport.loadedSession())
                // SnapshotKit's fixed iPad frame still runs inside the
                // checkout's iPhone simulator. Supply the regular-width trait
                // that a real iPad/Catalyst window contributes so this
                // reference actually guards the two-column presentation.
                .environment(\.horizontalSizeClass, .regular)
            }
        }
    }

    #Preview("Phone tabs") {
        MainView(
            report: PreviewSupport.loadedYearReportModel(),
            interfaceStyle: .tabs,
        )
        .environment(PreviewSupport.loadedModel())
        .environment(PreviewSupport.loadedSession())
        .whereBroadwayRoot()
    }

    #Preview("iPad and Mac split") {
        MainView(
            report: PreviewSupport.loadedYearReportModel(),
            interfaceStyle: .split,
        )
        .environment(PreviewSupport.loadedModel())
        .environment(PreviewSupport.loadedSession())
        .whereBroadwayRoot()
    }
#endif
