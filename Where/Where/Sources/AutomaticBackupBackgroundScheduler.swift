import BackgroundTasks
import Foundation
import os
import WhereCore

/// `BGProcessingTask` adapter for Core's scheduling seam. Registration stays
/// in the app target because only the application owns lifecycle callbacks.
@MainActor
final class AutomaticBackupBackgroundScheduler: AutomaticBackupTaskScheduling {
    static let identifier = "com.stuff.where.automatic-backup"

    private let scheduler: BGTaskScheduler
    private let logger = Logger(subsystem: "com.stuff.where", category: "AutomaticBackup")
    private var isRegistered = false

    init(scheduler: BGTaskScheduler = .shared) {
        self.scheduler = scheduler
    }

    func register(handler: @escaping @MainActor @Sendable () async -> Bool) {
        guard !isRegistered else { return }
        isRegistered = scheduler.register(
            forTaskWithIdentifier: Self.identifier,
            using: nil,
        ) { task in
            guard let processingTask = task as? BGProcessingTask else {
                task.setTaskCompleted(success: false)
                return
            }
            Task { @MainActor in
                let operation = Task { @MainActor in await handler() }
                processingTask.expirationHandler = { operation.cancel() }
                let succeeded = await operation.value
                processingTask.setTaskCompleted(success: succeeded && !operation.isCancelled)
            }
        }
        if !isRegistered {
            logger.error("BGTask registration failed")
        }
    }

    nonisolated func reconcile(isEnabled: Bool, earliestBeginDate: Date?) async {
        await reconcileOnMainActor(
            isEnabled: isEnabled,
            earliestBeginDate: earliestBeginDate,
        )
    }

    private func reconcileOnMainActor(isEnabled: Bool, earliestBeginDate: Date?) {
        scheduler.cancel(taskRequestWithIdentifier: Self.identifier)
        guard isEnabled else { return }

        let request = BGProcessingTaskRequest(identifier: Self.identifier)
        request.earliestBeginDate = earliestBeginDate
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        do {
            try scheduler.submit(request)
        } catch {
            logger
                .error("BGTask submission failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    func retryAfterFirstUnlock() {
        reconcileOnMainActor(
            isEnabled: true,
            earliestBeginDate: Date().addingTimeInterval(15 * 60),
        )
    }
}
