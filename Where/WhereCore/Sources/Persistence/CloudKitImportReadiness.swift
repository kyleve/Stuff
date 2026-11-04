import CoreData
import Foundation

@MainActor
public protocol CloudKitImportReadying: AnyObject {
    func start()
    func waitForImport() async -> Bool
}

/// Waits for SwiftData's initial CloudKit import without constructing application services.
@MainActor
public final class CloudKitImportReadiness: NSObject, CloudKitImportReadying {
    public struct Timeout: LocalizedError {
        public init() {}

        public var errorDescription: String? {
            "Where couldn’t finish checking iCloud. Choose this device or Off to continue safely."
        }
    }

    private enum State { case idle, observing, imported }
    private struct WaiterID: Hashable { let rawValue = UUID() }
    private var state = State.idle
    private var waiters: [WaiterID: CheckedContinuation<Bool, Never>] = [:]
    private var timeoutTask: Task<Void, Never>?
    private var waitTimeout: Duration = .seconds(10)

    @_spi(Testing)
    public convenience init(waitTimeout: Duration) {
        self.init()
        self.waitTimeout = waitTimeout
    }

    public func start() {
        guard case .idle = state else { return }
        state = .observing
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(eventChanged(_:)),
            name: NSPersistentCloudKitContainer.eventChangedNotification,
            object: nil,
        )
    }

    public func waitForImport() async -> Bool {
        if case .imported = state { return true }
        start()
        let waiterID = WaiterID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                guard !Task.isCancelled else { continuation.resume(returning: false); return }
                waiters[waiterID] = continuation
                if timeoutTask == nil {
                    let timeout = waitTimeout
                    timeoutTask = Task { [weak self] in
                        do { try await Task.sleep(for: timeout) }
                        catch { return } // Cancellation belongs to a completed or abandoned wait.
                        self?.finish(false)
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(waiterID) }
        }
    }

    private func cancel(_ waiterID: WaiterID) {
        waiters.removeValue(forKey: waiterID)?.resume(returning: false)
        if waiters.isEmpty {
            timeoutTask?.cancel()
            timeoutTask = nil
        }
    }

    #if DEBUG
        @_spi(Testing) public func receiveCompletedImport() {
            finish(true)
        }

        @_spi(Testing) public var waiterCount: Int {
            waiters.count
        }
    #endif

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
        if case .imported = state { return }
        if value {
            state = .imported
            NotificationCenter.default.removeObserver(self)
        }
        // A timeout does not discard a late successful import or poison the next attempt.
        timeoutTask?.cancel()
        timeoutTask = nil
        let pending = waiters
        waiters = [:]
        for continuation in pending.values {
            continuation.resume(returning: value)
        }
    }
}
