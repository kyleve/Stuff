import Foundation
import WhereCore

extension WhereFormat {
    static func recordingTimeZone(_ timeZone: TimeZone) -> String {
        timeZone.identifier.replacingOccurrences(of: "_", with: " ")
    }

    static func recordingCalendarOffset(_ context: RecordingCalendarContext) -> String {
        // A fixed zone formats the saved offset. The named zone's current offset can differ.
        guard let fixed = TimeZone(secondsFromGMT: context.secondsFromGMT) else {
            preconditionFailure("Reviewed calendar context has a validated offset")
        }
        let offset = context.secondsFromGMT == 0 ? "+00:00" :
            Date(timeIntervalSinceReferenceDate: 0).formatted(Date.FormatStyle(
                date: .omitted,
                time: .omitted,
                calendar: Calendar(identifier: .gregorian),
                timeZone: fixed,
            ).timeZone(.iso8601(.long)))
        return String(localized: .recordingCalendarOffset(
            recordingTimeZone(context.timeZone),
            offset,
        ))
    }

    static func recordingCalendarPeriod(_ segment: RecordingCalendarRecovery.Segment) -> String {
        guard let fixed = TimeZone(secondsFromGMT: segment.context.secondsFromGMT) else {
            preconditionFailure("Reviewed calendar context has a validated offset")
        }
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .standard,
            calendar: Calendar(identifier: .gregorian),
            timeZone: fixed,
        )
        return String(localized: .recordingCalendarLocalPeriod(
            segment.period.start.formatted(style),
            segment.period.end.formatted(style),
        ))
    }

    @MainActor
    static func recordingCalendarFailure(_ error: any Error) -> String {
        if let draft = error as? RecordingCalendarEditorModel.DraftError {
            switch draft {
                case .missingDevice: return String(localized: .recordingScopeChooseDevice)
                case .missingTimeZone: return String(localized: .recordingCalendarChooseZone)
                case .noPeriods: return String(localized: .recordingCalendarChoosePeriods)
            }
        }
        if error as? RecordingCalendarContext.ValidationError == .conflictingRecordedContext {
            return String(localized: .recordingCalendarConflictingContext)
        }
        if error is RecordingPeriod.ValidationError {
            return String(localized: .recordingScopeInvalidPeriod)
        }
        return String(localized: .recordingCalendarFailed)
    }
}
