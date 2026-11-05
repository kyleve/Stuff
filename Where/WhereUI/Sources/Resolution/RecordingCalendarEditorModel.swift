import Foundation
import Observation
import WhereCore

/// Collects an explicit historical zone and bounded periods. A changed draft cannot apply
/// the previous review, even when that review finishes after the edit.
@MainActor
@Observable
final class RecordingCalendarEditorModel: Identifiable {
    struct ID: Hashable { let value = UUID() }
    enum DraftError: Error, Equatable { case missingDevice, missingTimeZone, noPeriods }

    @MainActor
    @Observable
    final class PeriodSelection: Identifiable {
        let interval: RecordingScopeEditorModel.Interval
        var isIncluded = true
        nonisolated var id: RecordingScopeEditorModel.Interval.ID {
            interval.id
        }

        init(period: RecordingPeriod) {
            interval = .init(start: period.start, end: period.end)
        }
    }

    let id = ID()
    let controls: RecordingControlModel
    let zonePicker = RecordingTimeZonePickerModel()
    let names: [RecordingDeviceID: String]
    let devices: [RecordingDeviceID]
    var deviceID: RecordingDeviceID?
    var timeZone: TimeZone?
    let periods: [PeriodSelection]

    init(
        services: WhereServices,
        periods: [RecordingPeriod],
        devices: Set<RecordingDeviceID>,
        names: [RecordingDeviceID: String],
        selectedDevice: RecordingDeviceID?,
    ) {
        controls = RecordingControlModel(services: services)
        self.names = names
        self.devices = devices.union(selectedDevice.map { [$0] } ?? [])
            .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
        deviceID = selectedDevice
        self.periods = periods.map { .init(period: $0) }
    }

    var draft: Result<RecordingCalendarRecovery, any Error> {
        Result {
            guard let deviceID else { throw DraftError.missingDevice }
            guard let timeZone else { throw DraftError.missingTimeZone }
            let intervals = periods.filter(\.isIncluded).map(\.interval)
            guard !intervals.isEmpty else { throw DraftError.noPeriods }
            return try RecordingCalendarRecovery(
                deviceID: deviceID,
                periods: intervals.map { try .init(start: $0.start, end: $0.end) },
                timeZone: timeZone,
            )
        }
    }

    var reviewedRecovery: RecordingCalendarRecovery? {
        guard let proposal = controls.state.review?.proposal,
              case let .success(recovery) = draft,
              proposal.edits.map(\.edit) == recovery.edits else { return nil }
        return recovery
    }

    var canApply: Bool {
        controls.canApply && reviewedRecovery != nil
    }

    var canRetry: Bool {
        guard case let .failed(_, recovery) = controls.state,
              case let .success(draft) = draft else { return false }
        let edits = switch recovery {
            case let .review(edits, _): edits
            case let .save(review): review.proposal.edits.map(\.edit)
        }
        return edits == draft.edits
    }

    func review() async {
        guard case let .success(recovery) = draft else { return }
        await controls.review(recovery.edits)
    }

    func apply() async {
        guard canApply else { return }
        await controls.apply()
    }

    func retry() async {
        guard canRetry else { return }
        await controls.retry()
    }

    func deactivate() {
        controls.deactivate()
    }
}
