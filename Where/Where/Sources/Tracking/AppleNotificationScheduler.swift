import Foundation
import UserNotifications
import WhereCore

actor AppleNotificationScheduler: TrackingNotificationScheduling {
    private let notificationCenter: UNUserNotificationCenter

    init(notificationCenter: UNUserNotificationCenter = .current()) {
        self.notificationCenter = notificationCenter
    }

    func schedule(_ request: TrackingNotificationRequest) async {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default

        let interval = max(request.deliverAt.timeIntervalSinceNow, 1)
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: interval,
            repeats: false,
        )
        let notificationRequest = UNNotificationRequest(
            identifier: request.id,
            content: content,
            trigger: trigger,
        )

        try? await notificationCenter.add(notificationRequest)
    }

    func cancel(ids: [String]) async {
        guard !ids.isEmpty else { return }
        notificationCenter.removePendingNotificationRequests(withIdentifiers: ids)
    }
}
