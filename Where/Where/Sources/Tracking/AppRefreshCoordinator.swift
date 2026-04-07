import BackgroundTasks
import Foundation
import WhereData

@MainActor
final class AppRefreshCoordinator {
    static let taskIdentifier = "com.stuff.where.app-refresh"

    private let trackingController: BackgroundTrackingController

    init(trackingController: BackgroundTrackingController) {
        self.trackingController = trackingController
    }

    func register() {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: Self.taskIdentifier,
            using: nil,
        ) { [weak self] task in
            guard let refreshTask = task as? BGAppRefreshTask else {
                task.setTaskCompleted(success: false)
                return
            }

            self?.handle(refreshTask)
        }
    }

    func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: Self.taskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 4 * 60 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private func handle(_ task: BGAppRefreshTask) {
        schedule()
        task.expirationHandler = {}

        Task {
            await trackingController.refreshMonitoring()
            task.setTaskCompleted(success: true)
        }
    }
}
