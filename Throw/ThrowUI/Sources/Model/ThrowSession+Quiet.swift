import Foundation
import ThrowCore
import UIKit

extension ThrowSession {
    var isQuietNow: Bool {
        let now = dateProvider.now()
        if let temporaryWakeUntil, temporaryWakeUntil > now {
            return false
        }
        return quietSchedule.isQuiet(at: now, calendar: calendar)
    }

    public func wakeQuietly(for wake: TemporaryQuietWake) {
        temporaryWakeUntil = dateProvider.now().addingTimeInterval(wake.timeInterval)
        scheduleDemandReconciliation()
    }

    func expireTemporaryWakeIfNeeded() {
        guard let temporaryWakeUntil, temporaryWakeUntil <= dateProvider.now() else { return }
        self.temporaryWakeUntil = nil
    }

    func scheduleQuietBoundary() {
        quietBoundaryTask?.cancel()
        quietBoundaryTask = nil
        guard hasForegroundControllerScene else { return }
        let now = dateProvider.now()
        let boundary = quietSchedule.nextBoundary(after: now, calendar: calendar)
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
