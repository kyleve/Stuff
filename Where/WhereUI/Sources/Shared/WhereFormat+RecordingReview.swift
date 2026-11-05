import Foundation
import RegionKit
import WhereCore

extension WhereFormat {
    @MainActor
    static func recordingReviewFailure(_ recovery: RecordingChoiceModel.Recovery) -> String {
        switch recovery {
            case .load, .review: String(localized: .recordingReviewLoadFailed)
            case .save: String(localized: .recordingReviewSaveFailed)
        }
    }

    static func recordingAction(
        _ action: HistoryDecision.Action,
        names: [RecordingDeviceID: String],
    ) -> String {
        switch action {
            case let .select(deviceID):
                String(localized: .recordingReviewUseDevice(recordingDevice(
                    deviceID,
                    names: names,
                )))
            case .automatic: String(localized: .recordingReviewAutomatic)
        }
    }

    @MainActor
    static func recordingScopeError(_ error: any Error) -> String {
        if let error = error as? RecordingScopeEditorModel.DraftError {
            switch error {
                case .missingDevice: return String(localized: .recordingScopeChooseDevice)
                case .missingDate: return String(localized: .recordingScopeConfirmDate)
                case .invalidPeriods: return String(localized: .recordingScopeInvalidPeriod)
                case .mismatchedDevice: return String(localized: .recordingScopeDeviceMismatch)
            }
        }
        if error is RecordingPeriod
            .ValidationError { return String(localized: .recordingScopeInvalidPeriod) }
        return error.localizedDescription
    }

    /// Fixed intervals use UTC explicitly. Recorded dates remain CalendarDay values beside them.
    static func recordingInstant(_ date: Date) -> String {
        date.formatted(Date.FormatStyle(
            date: .abbreviated,
            time: .standard,
            calendar: Calendar(identifier: .gregorian),
            timeZone: .gmt,
        ))
    }

    static func recordingPeriod(_ period: RecordingPeriod) -> String {
        String(localized: .recordingReviewPeriod(
            recordingInstant(period.start),
            recordingInstant(period.end),
        ))
    }

    static func recordingDevice(
        _ deviceID: RecordingDeviceID,
        names: [RecordingDeviceID: String],
    ) -> String {
        names[deviceID] ??
            String(localized: .recordingReviewUnnamedDevice(deviceID.rawValue.uuidString))
    }

    static func recordingDays(_ days: RecordingHistorySelection.Days) -> String {
        let known = days.candidates.sorted().map {
            calendarDay($0, format: .dateTime.month(.abbreviated).day().year())
        }
        switch days {
            case .known:
                return known.isEmpty ? String(localized: .recordingReviewNoDates) : known
                    .formatted(.list(type: .and))
            case .unassigned:
                return (known + [String(localized: .recordingReviewUnknownDate)])
                    .formatted(.list(type: .and))
        }
    }

    static func recordingRegions(_ day: DayPresence) -> String {
        guard !day.regions.isEmpty else { return String(localized: .recordingReviewTransitOnly) }
        // Inspection precedes reporting groups. Here Other carries unresolved geography.
        return Region.inCanonicalOrder(day.regions).map {
            $0 == .other ? String(localized: .recordingReviewUnknownRegion) : $0.localizedName
        }.formatted(.list(type: .and))
    }

    static func recordingObservation(_ observation: RecordingObservation) -> String {
        let date: String = switch observation.recordingDay {
            case let .resolved(context): calendarDay(
                    context.day,
                    format: .dateTime.month(.abbreviated).day().year(),
                )
            case .unresolved: String(localized: .recordingReviewUnknownDate)
        }
        var regions = Region.inCanonicalOrder(observation.geography.knownRegions)
            .map(\.localizedName)
        if observation.geography
            .includesUnknownPresence
        {
            regions.append(String(localized: .recordingReviewUnknownRegion))
        }
        if regions.isEmpty { regions.append(String(localized: .recordingReviewExcluded)) }
        return ([date] + regions).formatted(.list(type: .and))
    }

    static func recordingSelection(
        _ selection: RecordingHistorySelection.Resolution,
        names: [RecordingDeviceID: String],
    ) -> String {
        switch selection {
            case let .chosen(deviceID):
                String(localized: .recordingReviewReasonChosen(recordingDevice(
                    deviceID,
                    names: names,
                )))
            case let .automatic(.onlyAvailableDevice(deviceID)):
                String(localized: .recordingReviewReasonOnly(recordingDevice(
                    deviceID,
                    names: names,
                )))
            case let .automatic(.movingOverStationary(deviceID)):
                String(localized: .recordingReviewReasonMoving(recordingDevice(
                    deviceID,
                    names: names,
                )))
            case .automatic(.agreement): String(localized: .recordingReviewReasonAgreement)
            case .automatic(.noEvidence): String(localized: .recordingReviewReasonNoEvidence)
            case .automatic(.conflict), .unresolved(.competingTracks):
                String(localized: .recordingReviewReasonConflict)
            case .automatic(.uncertain): String(localized: .recordingReviewReasonUncertain)
            case .unresolved(.recordingDay): String(localized: .recordingReviewReasonCalendar)
            case .unresolved(.eligibility): String(localized: .recordingReviewReasonEligibility)
            case .unresolved(.controls(
            .sourceConflict,
        )): String(localized: .recordingReviewReasonChoices)
            case .unresolved(.controls(
            .missingSourceChoices,
        )): String(localized: .recordingReviewReasonMissing)
            case let .unresolved(.controls(.selectedDeviceRemoved(deviceID))):
                String(localized: .recordingReviewReasonRemoved(recordingDevice(
                    deviceID,
                    names: names,
                )))
            case .unresolved(.controls(
            .unknownControls,
        )): String(localized: .recordingReviewReasonUnknown)
        }
    }
}
