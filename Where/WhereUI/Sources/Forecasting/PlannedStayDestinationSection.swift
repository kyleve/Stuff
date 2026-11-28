import RegionKit
import SFSafeSymbols
import SwiftUI

struct PlannedStayDestinationSection: View {
    let model: PlannedStayEditorModel
    let manage: () -> Void

    var body: some View {
        Section {
            PlannedStayRegionLink(model: model)
            if let region = model.region,
               let tracked = model.regionSelection.trackedRegions,
               !tracked.contains(region)
            {
                Text(String(localized: .plannedStayEditorUntracked))
                    .foregroundStyle(.secondary)
                Button(String(localized: .settingsRegionsManage), systemSymbol: .map) {
                    manage()
                }
            }
            if case let .failed(error) = model.regionSelection.loadState {
                Label(error.localizedDescription, systemSymbol: .exclamationmarkTriangle)
                    .foregroundStyle(.secondary)
                Button(String(localized: .commonRetry)) {
                    Task { await model.regionSelection.load() }
                }
            }
        } footer: {
            Text(String(localized: .plannedStayEditorDestinationFooter))
        }
    }
}

private struct PlannedStayRegionLink: View {
    let model: PlannedStayEditorModel

    var body: some View {
        NavigationLink {
            PlanningRegionPickerView(
                model: model.regionSelection,
                title: String(localized: .plannedStayEditorDestination),
                selectedRegion: model.region,
            ) { region in
                model.region = region
            }
        } label: {
            LabeledContent(String(localized: .plannedStayEditorDestination)) {
                Text(model.region?
                    .localizedName ?? String(localized: .plannedStayEditorChooseRegion))
            }
        }
    }
}

#if DEBUG
    #Preview("Planned stay") {
        PlannedStayEditorDestination(
            report: PreviewSupport.loadedYearReportModel(),
            mode: .new(initialRegion: nil),
        )
    }
#endif
