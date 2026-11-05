import Foundation
import Observation
import PeriscopeCore
import WhereCore

/// An explicit ignore intent and its exact reviewed preview. Changing the calendar draft
/// cannot reuse an earlier save; refreshed Core scopes retain the user's original intent.
@MainActor
@Observable
final class RecordingIgnoreEditorModel: Identifiable {
    struct ID: Hashable { let value = UUID() }
    enum DraftError: Error, Equatable { case notAnIgnore, noElapsedPeriod }
    enum Restoration { case resume, elapsed }
    enum Intent {
        case starting(deviceID: RecordingDeviceID, at: Date, timeZone: TimeZone)
        case changingEnd(RecordingIgnoreDecision)
        case resuming(RecordingIgnoreDecision, at: Date)
        case restoringElapsed(deviceID: RecordingDeviceID, period: RecordingPeriod, before: Date)
    }

    @MainActor
    @Observable
    final class EndDate {
        enum Origin {
            case new(start: Date)
            case saved(RecordingIgnoreDecision, RecordingIgnoreDecision.Until)
        }

        let origin: Origin
        let timeZone: TimeZone
        var day: CalendarDay

        init(origin: Origin, timeZone: TimeZone, day: CalendarDay) {
            self.origin = origin
            self.timeZone = timeZone
            self.day = day
        }

        var date: Date {
            get { day.startOfDay(in: RecordingScopeEditorModel.pickerCalendar) }
            set { day = CalendarDay(from: newValue, in: RecordingScopeEditorModel.pickerCalendar) }
        }

        func edit(for deviceID: RecordingDeviceID) throws -> RecordingControlEdit {
            let until: RecordingIgnoreDecision.Until
                // An unchanged saved day keeps its original boundary, even if zone rules changed.
                = if case let .saved(_, saved) = origin, saved.day == day
            {
                saved
            } else {
                try .init(day: day, timeZone: timeZone)
            }
            switch origin {
                case let .new(start):
                    return try .ignore(
                        deviceID: deviceID,
                        periods: [.init(start: start, end: until.end)],
                        change: .ignore(until),
                    )
                case let .saved(decision, _):
                    return try .changingIgnoreEnd(of: decision, until: until)
            }
        }
    }

    enum Draft {
        case until(EndDate)
        case restore(Restoration, RecordingControlEdit)
    }

    private struct Inspection {
        let proposal: RecordingControlEditCoordinator.Proposal
        let result: Result<RecordingIgnoreInspection, any Error>
    }

    let id = ID()
    let deviceID: RecordingDeviceID
    let name: String
    let draft: Draft
    let controls: RecordingControlModel
    private let services: WhereServices
    private var inspected: Inspection?
    private static let logger = WhereLog.session(RecordingReviewModelLog.self)

    init(services: WhereServices, name: String, intent: Intent) throws {
        self.services = services
        self.name = name
        controls = RecordingControlModel(services: services)
        switch intent {
            case let .starting(deviceID, start, timeZone):
                self.deviceID = deviceID
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = timeZone
                draft = .until(.init(
                    origin: .new(start: start),
                    timeZone: timeZone,
                    day: CalendarDay(from: start, in: calendar),
                ))
            case let .changingEnd(decision):
                try decision.validate()
                guard case let .ignore(until) = decision.change
                else { throw DraftError.notAnIgnore }
                deviceID = decision.deviceID
                draft = .until(.init(
                    origin: .saved(decision, until),
                    timeZone: until.timeZone,
                    day: until.day,
                ))
            case let .resuming(decision, cutoff):
                deviceID = decision.deviceID
                draft = try .restore(.resume, .resumingIgnore(decision, at: cutoff))
            case let .restoringElapsed(deviceID, period, cutoff):
                self.deviceID = deviceID
                try period.validate()
                guard period.start < cutoff else { throw DraftError.noElapsedPeriod }
                draft = try .restore(.elapsed, .ignore(
                    deviceID: deviceID,
                    periods: [.init(start: period.start, end: min(period.end, cutoff))],
                    change: .restoreEligibility,
                ))
        }
    }

    var edits: Result<[RecordingControlEdit], any Error> {
        Result {
            switch draft {
                case let .until(end): try [end.edit(for: deviceID)]
                case let .restore(_, edit): [edit]
            }
        }
    }

    var inspection: Result<RecordingIgnoreInspection, any Error>? {
        guard let review = controls.state.review, let inspected,
              case let .success(edits) = edits,
              review.requestedEdits == edits,
              review.proposal == inspected.proposal else { return nil }
        return inspected.result
    }

    var canApply: Bool {
        guard case .success? = inspection else { return false }
        return controls.canApply
    }

    var canRetry: Bool {
        guard case let .failed(_, recovery) = controls.state,
              case let .success(edits) = edits else { return false }
        let requested: [RecordingControlEdit] = switch recovery {
            case let .review(requested, _): requested
            case let .save(review): review.requestedEdits
        }
        return requested == edits
    }

    func review() async {
        guard case let .success(edits) = edits else { return }
        await controls.review(edits)
        inspect()
    }

    func apply() async {
        guard canApply else { return }
        await controls.apply()
        inspect()
    }

    func retry() async {
        guard canRetry else { return }
        await controls.retry()
        inspect()
    }

    func deactivate() {
        controls.deactivate()
        inspected = nil
    }

    private func inspect() {
        guard let proposal = controls.state.review?.proposal else { inspected = nil; return }
        guard inspected?.proposal != proposal else { return }
        let result = Result { try services.recordingControlEdits.inspectIgnore(proposal) }
        if case let .failure(error) = result {
            Self.logger.operationFailed(error: .restricted(.errorDetails, error))
        }
        inspected = Inspection(proposal: proposal, result: result)
    }
}
