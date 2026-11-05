import Foundation
import Observation
import WhereCore

/// An unsaved scope draft. Fixed intervals stay separate; a logical date is only a query
/// until Core establishes its complete recorded calendar coverage in the next preview.
@MainActor
@Observable
final class RecordingScopeEditorModel: Identifiable {
    struct ID: Hashable { let value = UUID() }
    @MainActor
    @Observable
    final class Interval: Identifiable {
        struct ID: Hashable { let value = UUID() }
        let id = ID()
        var start: Date
        var end: Date

        init(start: Date, end: Date) {
            self.start = start
            self.end = end
        }
    }

    enum Kind { case periods, recordingDay }
    enum DraftError: Error { case missingDevice, missingDate, invalidPeriods, mismatchedDevice }

    @MainActor
    @Observable
    final class Day {
        enum Selection {
            case suggested(CalendarDay)
            case selected(CalendarDay)

            var day: CalendarDay {
                switch self {
                    case let .suggested(day), let .selected(day): day
                }
            }
        }

        var deviceID: RecordingDeviceID?
        var selection: Selection

        init(deviceID: RecordingDeviceID?, selection: Selection) {
            self.deviceID = deviceID
            self.selection = selection
        }

        var date: Date {
            get { selection.day.startOfDay(in: RecordingScopeEditorModel.pickerCalendar) }
            set {
                selection = .selected(CalendarDay(
                    from: newValue,
                    in: RecordingScopeEditorModel.pickerCalendar,
                ))
            }
        }

        var needsDateConfirmation: Bool {
            if case .suggested = selection { return true }
            return false
        }

        func confirmDate() {
            selection = .selected(selection.day)
        }
    }

    enum Draft {
        case periods([Interval])
        case recordingDay(Day)
    }

    let id = ID()
    let action: HistoryDecision.Action
    let names: [RecordingDeviceID: String]
    let devices: [RecordingDeviceID]
    private let initialPeriods: [RecordingPeriod]
    private let suggestedDay: Day
    var draft: Draft

    /// UTC is a neutral DatePicker projection for CalendarDay, not a recovered recording zone.
    nonisolated static let pickerCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }()

    init(presentation: RecordingChoicePresentation, originalPeriods: [RecordingPeriod]) {
        action = presentation.request.action
        names = presentation.names
        var available = Set(presentation.names.keys)
        if case let .comparison(comparison) = presentation
            .result { available.formUnion(comparison.tracks.map(\.id)) }
        if case let .recordingDay(deviceID, _) = presentation.request
            .scope { available.insert(deviceID) }
        devices = available.sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        initialPeriods = presentation.periods.isEmpty ? originalPeriods : presentation.periods
        precondition(!initialPeriods.isEmpty, "An inspected choice retains its original periods")
        let deviceID: RecordingDeviceID? = switch action {
            case let .select(deviceID): deviceID
            case .automatic: nil
        }
        let candidates: Set<CalendarDay> = switch presentation.result {
            case let .comparison(comparison):
                comparison.tracks.filter { deviceID == nil || $0.id == deviceID }
                    .reduce(into: []) { $0.formUnion($1.days.candidates) }
            case .needsCalendarContext, .absentRecordingDay: []
        }
        // The fallback is a visibly unconfirmed picker draft. It never assigns an observation.
        let seed = CalendarDay(
            from: initialPeriods[0].start,
            in: Self.pickerCalendar,
        )
        suggestedDay = Day(
            deviceID: deviceID,
            selection: candidates.sorted().first.map(Day.Selection.selected) ?? .suggested(seed),
        )
        switch presentation.request.scope {
            case .periods:
                draft = .periods(initialPeriods.map { Interval(start: $0.start, end: $0.end) })
            case let .recordingDay(deviceID, day):
                draft = .recordingDay(Day(deviceID: deviceID, selection: .selected(day)))
        }
    }

    var kind: Kind {
        get {
            switch draft {
                case .periods: .periods
                case .recordingDay: .recordingDay
            }
        }
        set {
            guard kind != newValue else { return }
            switch newValue {
                case .periods:
                    draft = .periods(initialPeriods.map { Interval(start: $0.start, end: $0.end) })
                case .recordingDay:
                    draft = .recordingDay(Day(
                        deviceID: suggestedDay.deviceID,
                        selection: suggestedDay.selection,
                    ))
            }
        }
    }

    var request: Result<RecordingChoiceRequest, any Error> {
        Result {
            let scope: RecordingChoiceRequest.Scope
            switch draft {
                case let .periods(intervals):
                    guard !intervals.isEmpty else { throw DraftError.invalidPeriods }
                    scope = try .periods(intervals.map { try RecordingPeriod(
                        start: $0.start,
                        end: $0.end,
                    ) })
                case let .recordingDay(day):
                    guard let deviceID = day.deviceID else { throw DraftError.missingDevice }
                    guard case let .selected(date) = day.selection
                    else { throw DraftError.missingDate }
                    if case let .select(selected) = action, deviceID != selected {
                        throw DraftError.mismatchedDevice
                    }
                    scope = .recordingDay(deviceID: deviceID, day: date)
            }
            return RecordingChoiceRequest(scope: scope, action: action)
        }
    }
}
