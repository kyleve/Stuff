import Foundation
import Observation
import ThrowCore

/// Owns an editable quiet-hours draft while the session retains its last valid schedule.
@MainActor
@Observable
final class QuietHoursSettingsModel {
    private let session: ThrowSession

    var isEnabled: Bool {
        didSet {
            guard oldValue != isEnabled else { return }
            applyValidSchedule()
        }
    }

    var start: Date {
        didSet {
            guard oldValue != start else { return }
            applyValidSchedule()
        }
    }

    var end: Date {
        didSet {
            guard oldValue != end else { return }
            applyValidSchedule()
        }
    }

    init(session: ThrowSession) {
        self.session = session
        isEnabled = session.quietHoursEnabled
        start = session.quietStart
        end = session.quietEnd
    }

    var postLaunchFailures: [ThrowPostLaunchFailure] {
        session.postLaunchFailures(for: .quietHours)
    }

    var scheduleIsValid: Bool {
        validatedSchedule != nil
    }

    private var validatedSchedule: QuietSchedule? {
        guard isEnabled else { return .disabled }
        let startComponents = session.calendar.dateComponents([.hour, .minute], from: start)
        let endComponents = session.calendar.dateComponents([.hour, .minute], from: end)
        guard let startHour = startComponents.hour,
              let startMinute = startComponents.minute,
              let endHour = endComponents.hour,
              let endMinute = endComponents.minute
        else {
            assertionFailure("The current calendar must produce quiet-hours components")
            return nil
        }
        do {
            return try QuietSchedule(
                start: LocalTime(hour: startHour, minute: startMinute),
                end: LocalTime(hour: endHour, minute: endMinute),
            )
        } catch ThrowValidationError.invalidQuietInterval {
            return nil
        } catch {
            assertionFailure("Date-picker quiet hours must be in range: \(error)")
            return nil
        }
    }

    private func applyValidSchedule() {
        guard let validatedSchedule else { return }
        session.updateQuietSchedule(validatedSchedule)
    }
}
