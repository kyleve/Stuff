import RegionKit
import SFSafeSymbols
import SnapshotKit
import SwiftUI

/// Shared searchable, grouped single-region picker for a stay or Home.
struct PlanningRegionPickerView: View {
    @Bindable var model: PlanningRegionSelectionModel
    let title: String
    let selectedRegion: Region?
    let onSelect: @MainActor (Region) async throws -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if case let .failed(error) = model.loadState {
                PlanningRegionLoadFailure(
                    message: error.localizedDescription,
                    retry: { Task { await model.load() } },
                )
            }
            if case let .failed(error) = model.selectionState {
                Section {
                    Label(error.localizedDescription, systemSymbol: .exclamationmarkTriangle)
                        .foregroundStyle(.red)
                }
            }
            if model.isSearching {
                ForEach(model.filteredRegions, id: \.self, content: regionRow)
            } else {
                GroupedRegionSections(grouping: model.grouping, row: regionRow)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $model.searchText, prompt: String(localized: .regionPickerSearchPrompt))
        .disabled(model.isSaving)
        .overlay {
            if model.isSearching, model.filteredRegions.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .task {
            if case .idle = model.loadState {
                await model.load()
            }
        }
    }

    private func regionRow(_ region: Region) -> PlanningRegionButton {
        PlanningRegionButton(
            region: region,
            selectedRegion: selectedRegion,
            model: model,
            onSelect: onSelect,
            dismiss: dismiss.callAsFunction,
        )
    }
}

private struct PlanningRegionLoadFailure: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        Section {
            Label(message, systemSymbol: .exclamationmarkTriangle)
                .foregroundStyle(.secondary)
            Button(String(localized: .commonRetry)) {
                retry()
            }
        }
    }
}

#if DEBUG
    extension PlanningRegionPickerView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let homeModel = PlanningRegionSelectionModel(report: PreviewSupport
                .loadedYearReportModel())
            whereSnapshot(
                name: "Home",
                configurations: .fullContentScreenRepresentative,
                onReadyToMeasure: { await homeModel.load() },
            ) {
                NavigationStack {
                    PlanningRegionPickerView(
                        model: homeModel,
                        title: String(localized: .plannedStaysHomeRegion),
                        selectedRegion: .california,
                        onSelect: { _ in },
                    )
                }
            }
            whereSnapshot(name: "Search", configurations: .fullContentPhoneLightDark) {
                NavigationStack {
                    PlanningRegionPickerView(
                        model: searchModel(),
                        title: String(localized: .plannedStayEditorDestination),
                        selectedRegion: .newYork,
                        onSelect: { _ in },
                    )
                }
            }
        }
    }

    extension PlanningRegionPickerView {
        fileprivate static func searchModel() -> PlanningRegionSelectionModel {
            let model = PlanningRegionSelectionModel(report: PreviewSupport.loadedYearReportModel())
            model.searchText = "New"
            return model
        }
    }

    #Preview { PlanningRegionPickerView.snapshotPreviews }
#endif
