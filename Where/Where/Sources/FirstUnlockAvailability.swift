import Foundation
import os
import UIKit

/// Probes Class C file protection without opening the data store or querying
/// Keychain. Unlike UIApplication's flag, Class C remains available on relock.
actor FirstUnlockAvailability {
    private let marker: URL
    private let isDeviceUnlocked: @Sendable () async -> Bool
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
            return unlocked
        }
    }
}
