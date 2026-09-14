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
    @Environment(\.regionStyles) private var regionStyles
    @Environment(\.stylesheet) private var stylesheet

    var body: some View {
        List {
            if case let .failed(message) = model.loadState {
                Section {
                    Label(message, systemSymbol: .exclamationmarkTriangle)
                        .foregroundStyle(.secondary)
                    Button(String(localized: .commonRetry)) {
                        Task { await model.load() }
                    }
                }
            }
            if case let .failed(message) = model.selectionState {
                Section {
                    Label(message, systemSymbol: .exclamationmarkTriangle)
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
        .disabled(model.selectionState == .saving)
        .overlay {
            if model.isSearching, model.filteredRegions.isEmpty {
                ContentUnavailableView.search(text: model.searchText)
            }
        }
        .task {
            if case .idle = model.loadState { await model.load() }
        }
    }

    private func regionRow(_ region: Region) -> some View {
        Button {
            Task {
                if await model.select(region, commit: onSelect) { dismiss() }
            }
        } label: {
            HStack(spacing: stylesheet.spacing.medium) {
                Text(regionStyles.style(for: region).emoji)
                    .accessibilityHidden(true)
                Text(region.localizedName)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
                if selectedRegion == region {
                    Image(systemSymbol: .checkmark)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(.rect)
        }
        .accessibilityAddTraits(selectedRegion == region ? [.isSelected] : [])
    }
}

#if DEBUG
    extension PlanningRegionPickerView: SnapshotProviding {
        static var snapshots: [SnapshotCase] {
            let homeModel = PlanningRegionSelectionModel(report: PreviewSupport
                .loadedYearReportModel())
            whereSnapshot(
                name: "Home",
                configurations: .fullContentScreenDefaults,
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
