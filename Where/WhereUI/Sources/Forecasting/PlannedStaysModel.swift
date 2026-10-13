import Foundation
import Observation
import RegionKit
import WhereCore

/// Planner presentation state over the report's shared planning snapshot.
@MainActor
@Observable
final class PlannedStaysModel {
    enum SaveState {
        case idle
        case saving
        case failed(Error)
    }

    let report: YearReportModel
    let regionSelection: PlanningRegionSelectionModel
    private let initialRegion: Region?
    var editor: PlannedStayEditorModel?
    var showsPast = false
    private(set) var saveState: SaveState = .idle

    init(report: YearReportModel, initialRegion: Region?) {
        self.report = report
        self.initialRegion = initialRegion
        regionSelection = PlanningRegionSelectionModel(report: report)
    }

    var upcoming: [PlannedStay] {
        sortedStays.filter { $0.departure.latest >= report.forecasts.today }
    }

    var past: [PlannedStay] {
        Array(sortedStays.filter { $0.departure.latest < report.forecasts.today }.reversed())
    }

    var overlaps: [PlannedStayOverlap] {
        report.forecasts.planning.overlaps(asOf: report.forecasts.today)
    }

    var isSaving: Bool {
        if case .saving = saveState { return true }
        return false
    }

    private var sortedStays: [PlannedStay] {
        report.forecasts.planning.stays.sorted {
            if $0.arrival.earliest != $1.arrival.earliest {
                return $0.arrival.earliest < $1.arrival.earliest
            }
            return $0.id.rawValue.uuidString < $1.id.rawValue.uuidString
        }
    }

    func add() {
        editor = PlannedStayEditorModel(report: report, mode: .new(initialRegion: initialRegion))
    }

    func edit(_ stay: PlannedStay) {
        editor = PlannedStayEditorModel(report: report, mode: .edit(stay))
    }

    func usesDefiniteOverlap(_ stay: PlannedStay) -> Bool {
        overlaps.contains {
            ($0.firstStayID == stay.id || $0.secondStayID == stay.id) && $0.certainRange != nil
        }
    }

    func usesPossibleOverlap(_ stay: PlannedStay) -> Bool {
        overlaps.contains {
            ($0.firstStayID == stay.id || $0.secondStayID == stay.id) && $0.certainRange == nil
        }
    }

    func usePastTravelPattern() async {
        guard !isSaving, report.forecasts.planning.homeRegion != nil else { return }
        saveState = .saving
        do {
            try await report.forecasts.setHomeRegion(nil)
            saveState = .idle
        } catch {
            saveState = .failed(error)
        }
    }

    func load() async {
        if !report.forecasts.hasLoaded { await report.forecasts.refresh() }
        await regionSelection.load()
    }
}
