import Foundation
import UIKit

extension ThrowSession {
    var isQuietNow: Bool {
        let now = dateProvider.now()
        if let temporaryWakeUntil, temporaryWakeUntil > now {
            return false
        }
        do {
            return try quietSchedule().isQuiet(at: now, calendar: calendar)
        } catch {
            settingsFailure = error.localizedDescription
            return false
        }
    }

    public func wakeQuietly(forMinutes minutes: Int) {
        guard [15, 30, 60].contains(minutes) else {
            assertionFailure("Unsupported temporary quiet wake duration")
            return
        }
        temporaryWakeUntil = dateProvider.now().addingTimeInterval(Double(minutes * 60))
        scheduleDemandReconciliation()
    }

    func expireTemporaryWakeIfNeeded() {
        guard let temporaryWakeUntil, temporaryWakeUntil <= dateProvider.now() else { return }
        self.temporaryWakeUntil = nil
    }

    func scheduleQuietBoundary() {
        quietBoundaryTask?.cancel()
        quietBoundaryTask = nil
        guard isForeground else { return }
        let now = dateProvider.now()
        let boundary: Date?
        do {
            boundary = try quietSchedule().nextBoundary(after: now, calendar: calendar)
        } catch {
            settingsFailure = error.localizedDescription
            return
        }
        let wake = [boundary, temporaryWakeUntil]
            .compactMap(\.self)
            .filter { $0 > now }
            .min()
        guard let wake else { return }
        quietBoundaryTask = Task(name: "Throw quiet boundary") { [weak self] in
            do {
                try await Task.sleep(for: .seconds(wake.timeIntervalSince(now)))
            } catch is CancellationError {
                return
            } catch {
                assertionFailure("Unexpected quiet-boundary timer failure: \(error)")
                return
            }
            guard Task.isCancelled == false else { return }
            self?.expireTemporaryWakeIfNeeded()
            self?.scheduleDemandReconciliation()
        }
    }

    func installTimeChangeObservers() {
        guard timeChangeTasks.isEmpty else { return }
        let names: [Notification.Name] = [
            UIApplication.significantTimeChangeNotification,
            .NSSystemTimeZoneDidChange,
            .NSCalendarDayChanged,
        ]
        timeChangeTasks = names.map { name in
            Task(name: "Throw observe time changes") { [weak self] in
                for await _ in NotificationCenter.default.notifications(named: name) {
                    guard Task.isCancelled == false else { return }
                    self?.expireTemporaryWakeIfNeeded()
                    self?.scheduleDemandReconciliation()
                }
            }
        }
    }
}
