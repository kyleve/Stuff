import CoreData
import Foundation

/// Waits for SwiftData's initial CloudKit import without constructing application services.
@MainActor
public final class CloudKitImportReadiness: NSObject {
    public struct Timeout: LocalizedError {
        public init() {}

        public var errorDescription: String? {
            "Where couldn’t finish checking iCloud. Choose this device or Off to continue safely."
        }
    }

    private var continuation: CheckedContinuation<Bool, Never>?
    private var finishedValue: Bool?
    private var timeoutTask: Task<Void, Never>?

    public func start() {
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventChanged(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
        )
    }

    public func waitForImport() async -> Bool {
        if let finishedValue { return finishedValue }
        timeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            self?.finish(false)
        }
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation = $0 }
        } onCancel: {
            Task { @MainActor [weak self] in self?.finish(false) }
        }
    }

    @objc private nonisolated func eventChanged(_ notification: Notification) {
        guard let event = notification
            .userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
            as? NSPersistentCloudKitContainer.Event
        else { return }
        let imported = event.type == .import && event.endDate != nil && event.succeeded
        guard imported else { return }
        Task { @MainActor [weak self] in self?.finish(true) }
    }

    private func finish(_ value: Bool) {
        guard finishedValue == nil else { return }
        finishedValue = value
        timeoutTask?.cancel()
        timeoutTask = nil
        NotificationCenter.default.removeObserver(self)
        continuation?.resume(returning: value)
        continuation = nil
    }
}
