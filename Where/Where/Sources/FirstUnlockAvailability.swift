import Foundation
import os
import UIKit

/// Probes Class C file protection without opening the data store or querying
/// Keychain. Unlike UIApplication's flag, Class C remains available on relock.
actor FirstUnlockAvailability {
    private let marker: URL
    private let isDeviceUnlocked: @Sendable () async -> Bool
    private var hasBeenAvailable = false
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private let logger = Logger(subsystem: "com.stuff.where", category: "AutomaticBackup")

    init(marker: URL, isDeviceUnlocked: @escaping @Sendable () async -> Bool) {
        self.marker = marker
        self.isDeviceUnlocked = isDeviceUnlocked
    }

    static func applicationSupport() -> FirstUnlockAvailability {
        FirstUnlockAvailability(marker: URL.applicationSupportDirectory
            .appendingPathComponent("Where/first-unlock-probe", isDirectory: false))
        {
            await MainActor.run { UIApplication.shared.isProtectedDataAvailable }
        }
    }

    func isAvailable() async -> Bool {
        if hasBeenAvailable { return true }
        let unlocked = await isDeviceUnlocked()
        do {
            if !FileManager.default.fileExists(atPath: marker.path) {
                try FileManager.default.createDirectory(
                    at: marker.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                )
                try Data([1]).write(to: marker, options: [
                    .completeFileProtectionUntilFirstUserAuthentication,
                    .withoutOverwriting,
                ])
            }
            _ = try Data(contentsOf: marker)
            protectedDataDidBecomeAvailable()
            return true
        } catch {
            if unlocked {
                logger
                    .warning(
                        "First-unlock probe unavailable: \(error.localizedDescription, privacy: .public)",
                    )
            }
            // The system's unlocked state is authoritative; never block
            // recording because creating the marker failed (for example ENOSPC).
            if unlocked { protectedDataDidBecomeAvailable() }
            return hasBeenAvailable
        }
    }

    /// All launch entry points join this barrier, including RootView promotion.
    func waitUntilAvailable() async throws {
        if await isAvailable() {
            try Task.checkCancellation()
            return
        }
        let token = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<
                Void,
                Error
            >) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if hasBeenAvailable {
                    continuation.resume()
                } else {
                    waiters[token] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(token) }
        }
    }

    func protectedDataDidBecomeAvailable() {
        hasBeenAvailable = true
        let pending = waiters.values
        waiters.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }

    private func cancelWaiter(_ token: UUID) {
        waiters.removeValue(forKey: token)?.resume(throwing: CancellationError())
    }

    #if DEBUG
        @_spi(Testing) public var waitingCallerCount: Int {
            waiters.count
        }
    #endif
}
