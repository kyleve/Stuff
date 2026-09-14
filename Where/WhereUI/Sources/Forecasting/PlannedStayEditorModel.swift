import Foundation
import Observation
import RegionKit
import WhereCore

/// An independent stay draft. Calendar-day boundaries survive device timezone
/// changes; only the date-picker projections use the report's calendar.
@MainActor
@Observable
final class PlannedStayEditorModel: Identifiable {
    enum SaveState: Equatable {
        case idle
        case saving
        case failed(String)
    }

    struct Boundary {
        enum Selection {
            case exact(Date)
            case flexible(earliest: Date, latest: Date)
        }

        private var selection: Selection

        init(date: Date) {
            selection = .exact(date)
        }

        init(window: PlannedStay.DateWindow, calendar: Calendar) {
            let earliest = window.earliest.startOfDay(in: calendar)
            if window.isExact {
                selection = .exact(earliest)
            } else {
                selection = .flexible(
                    earliest: earliest,
                    latest: window.latest.startOfDay(in: calendar),
                )
            }
        }

        var isFlexible: Bool {
            get {
                switch selection {
                    case .exact: false
                    case .flexible: true
                }
            }
            set {
                guard newValue != isFlexible else { return }
                selection = newValue
                    ? .flexible(earliest: earliest, latest: earliest)
                    : .exact(earliest)
            }
        }

        var earliest: Date {
            get {
                switch selection {
                    case let .exact(date): date
                    case let .flexible(earliest, _): earliest
                }
            }
            set {
                switch selection {
                    case .exact:
                        selection = .exact(newValue)
                    case let .flexible(_, latest):
                        selection = .flexible(earliest: newValue, latest: max(newValue, latest))
                }
            }
        }

        var latest: Date {
            get {
                switch selection {
                    case let .exact(date): date
                    case let .flexible(_, latest): latest
                }
            }
            set {
                switch selection {
                    case .exact:
                        selection = .exact(newValue)
                    case let .flexible(earliest, _):
                        selection = .flexible(earliest: min(earliest, newValue), latest: newValue)
                }
            }
        }

        func window(in calendar: Calendar) throws -> PlannedStay.DateWindow {
            try PlannedStay.DateWindow(
                earliest: CalendarDay(from: earliest, in: calendar),
                latest: CalendarDay(from: latest, in: calendar),
            )
        }
    }

    let report: YearReportModel
    nonisolated let stayID: PlannedStay.ID
    let regionSelection: PlanningRegionSelectionModel
    let isEditing: Bool
    var region: Region?
    var arrival: Boundary
    var departure: Boundary
    private(set) var saveState: SaveState = .idle

    init(report: YearReportModel, stay: PlannedStay?, initialRegion: Region?) {
        self.report = report
        regionSelection = PlanningRegionSelectionModel(report: report)
        stayID = stay?.id ?? PlannedStay.ID(rawValue: UUID())
        isEditing = stay != nil
        region = stay?.region ?? initialRegion
        if let stay {
            arrival = Boundary(window: stay.arrival, calendar: report.calendar)
            departure = Boundary(window: stay.departure, calendar: report.calendar)
        } else {
            let today = report.calendar.startOfDay(for: report.referenceDate)
            arrival = Boundary(date: today)
            departure = Boundary(date: today)
        }
    }

    var isSaving: Bool {
        saveState == .saving
    }

    nonisolated var id: PlannedStay.ID {
        stayID
    }

    var validationMessage: String? {
        guard region != nil else {
            return String(localized: .plannedStayEditorDestinationRequired)
        }
        switch draft {
            case .success: return nil
            case .failure: return String(localized: .plannedStayEditorInvalidDates)
        }
    }

    var canSave: Bool {
        !isSaving && validationMessage == nil
    }

    var draft: Result<PlannedStay, Error> {
        Result {
            guard let region else { throw DraftError.missingRegion }
            return try PlannedStay(
                id: stayID,
                region: region,
                arrival: arrival.window(in: report.calendar),
                departure: departure.window(in: report.calendar),
            )
        }
    }

    var overlaps: [PlannedStayOverlap] {
        guard case let .success(stay) = draft else { return [] }
        let snapshot = PlanningSnapshot(
            stays: report.forecasts.planning.stays.filter { $0.id != stayID } + [stay],
            homeRegion: report.forecasts.planning.homeRegion,
        )
        return snapshot.overlaps(
            asOf: CalendarDay(from: report.referenceDate, in: report.calendar),
        ).filter { $0.firstStayID == stayID || $0.secondStayID == stayID }
    }

    var hasDefiniteOverlap: Bool {
        overlaps.contains { $0.certainRange != nil }
    }

    var hasPossibleOverlap: Bool {
        overlaps.contains { $0.certainRange == nil }
    }

    func load() async {
        if !report.forecasts.hasLoaded { await report.forecasts.refresh() }
        await regionSelection.load()
    }

    /// Returns success only after the independent revision has committed.
    func save() async -> Bool {
        guard canSave else { return false }
        saveState = .saving
        do {
            let stay = try draft.get()
            if isEditing {
                try await report.forecasts.update(stay: stay)
            } else {
                try await report.forecasts.create(stay: stay)
            }
            saveState = .idle
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            return false
        }
    }

    func delete() async -> Bool {
        guard isEditing, !isSaving else { return false }
        saveState = .saving
        do {
            try await report.forecasts.delete(stayID: stayID)
            saveState = .idle
            return true
        } catch {
            saveState = .failed(error.localizedDescription)
            return false
        }
    }

    private enum DraftError: Error {
        case missingRegion
    }
}
