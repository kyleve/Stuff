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
        case failed(String)
    }

    enum SelectionState: Equatable {
        case idle
        case saving
        case failed(String)
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
            Self.logger(attachments: [.error(error, name: "planning-regions-error")]) {
                .loadFailed(description: error.localizedDescription)
            }
            loadState = .failed(error.localizedDescription)
        }
    }

    func select(
        _ region: Region,
        commit: @MainActor (Region) async throws -> Void,
    ) async -> Bool {
        guard selectionState != .saving else { return false }
        selectionState = .saving
        do {
            try await commit(region)
            selectionState = .idle
            return true
        } catch {
            selectionState = .failed(error.localizedDescription)
            return false
        }
    }
}
