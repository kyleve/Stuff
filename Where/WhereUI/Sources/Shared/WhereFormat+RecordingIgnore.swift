import Foundation
import WhereCore

extension WhereFormat {
    static func recordingIgnoreResolution(_ resolution: RecordingIgnoreResolver
        .Resolution) -> String
    {
        switch resolution {
            case .eligible: String(localized: .recordingIgnoreEligible)
            case .ignored: String(localized: .recordingIgnoreIgnored)
            case .conflict: String(localized: .recordingIgnoreConflict)
            case .incomplete: String(localized: .recordingIgnoreIncomplete)
        }
    }

    static func recordingIgnoreDecision(_ decision: RecordingIgnoreDecision) -> String {
        switch decision.change {
            case let .ignore(until):
                String(localized: .recordingIgnoreThrough(calendarDay(
                    until.day,
                    format: .dateTime.month(.abbreviated).day().year(),
                )))
            case .restoreEligibility:
                String(localized: .recordingIgnoreRestored)
        }
    }

    static func recordingIgnoreOutcome(
        _ outcome: RecordingIgnoreInspection.Outcome,
        deviceID: RecordingDeviceID,
    ) -> String {
        switch outcome {
            case .automatic(.eligible): String(localized: .recordingIgnoreEligible)
            case .automatic(.ignored): String(localized: .recordingIgnoreIgnored)
            case .automatic(.removed): String(localized: .recordingIgnoreRemoved)
            case .automatic(.conflict): String(localized: .recordingIgnoreConflict)
            case .automatic(.incomplete): String(localized: .recordingIgnoreIncomplete)
            case let .selected(selected):
                selected == deviceID ? String(localized: .recordingIgnoreSelected) :
                    String(localized: .recordingIgnoreOtherSelected)
            case .unresolved(.sourceConflict): String(localized: .recordingReviewReasonChoices)
            case .unresolved(.missingSourceChoices): String(
                    localized: .recordingReviewReasonMissing,
                )
            case .unresolved(.selectedDeviceRemoved): String(
                    localized: .recordingIgnoreSelectedRemoved,
                )
            case .unresolved(.unknownControls): String(localized: .recordingReviewReasonUnknown)
        }
    }

    @MainActor
    static func recordingIgnoreFailure(_ error: any Error) -> String {
        if let error = error as? RecordingIgnoreEditorModel.DraftError {
            switch error {
                case .notAnIgnore: return String(localized: .recordingIgnoreFailed)
                case .noElapsedPeriod: return String(localized: .recordingIgnoreNoElapsed)
            }
        }
        if let error = error as? RecordingControlEdit.ValidationError {
            switch error {
                case .notAnIgnore: return String(localized: .recordingIgnoreFailed)
                case .ignoreAlreadyEnded: return String(localized: .recordingIgnoreEnded)
            }
        }
        if error is RecordingPeriod.ValidationError || error is RecordingIgnoreDecision
            .ValidationError
        {
            return String(localized: .recordingIgnoreInvalidEnd)
        }
        if error is DataCompatibilityAccess.AccessError {
            return String(localized: .recordingIgnoreUnavailable)
        }
        return String(localized: .recordingIgnoreFailed)
    }
}
