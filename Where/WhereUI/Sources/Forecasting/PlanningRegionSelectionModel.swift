import Foundation
import Observation
import RegionKit
import WhereCore

/// Selects one supported destination without modifying automatic tracking.
@MainActor
@Observable
final class PlanningRegionSelectionModel {
    enum LoadState {
        case idle
        case loading
        case loaded([PrimaryRegion])
        case failed(Error)
    }

    enum SelectionState {
        case idle
        case saving
        case failed(Error)
    }

    let report: YearReportModel
    let available = PrimaryRegionSelectionModel.usRegions
    var searchText = ""
    private(set) var loadState: LoadState = .idle
    private(set) var selectionState: SelectionState = .idle

    private static let logger = WhereLog.session(PlanningRegionSelectionModelLog.self)

    init(report: YearReportModel) {
        self.report = report
    }

    var trackedRegions: [Region]? {
        guard case let .loaded(regions) = loadState else { return nil }
        return regions.map(\.region)
    }

    var grouping: RegionGrouping {
        RegionGrouping(
            available: available,
            primary: trackedRegions ?? [],
            usedThisYear: Set(report.report?.totals.keys.map(\.self) ?? []),
        )
    }

    var isSaving: Bool {
        if case .saving = selectionState { return true }
        return false
    }

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var filteredRegions: [Region] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return available.filter { $0.localizedName.localizedCaseInsensitiveContains(query) }
    }

    func load() async {
        if case .loading = loadState { return }
        loadState = .loading
        do {
            let regions = try await report.services.primaryRegions()
            guard !Task.isCancelled else {
                loadState = .idle
                return
            }
            loadState = .loaded(regions)
        } catch {
            guard !Task.isCancelled else {
                loadState = .idle
                return
            }
            Self.logger.loadFailed(error: .restricted(.errorDetails, error))
            loadState = .failed(error)
        }
    }

    func select(
        _ region: Region,
        commit: @MainActor (Region) async throws -> Void,
    ) async -> Bool {
        guard !isSaving else { return false }
        selectionState = .saving
        do {
            try await commit(region)
            selectionState = .idle
            return true
        } catch {
            selectionState = .failed(error)
            return false
        }
    }
}
