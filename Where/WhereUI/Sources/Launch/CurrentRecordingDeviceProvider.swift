import Foundation
import UIKit
import WhereCore

/// Builds the local installation identity at the app composition boundary.
///
/// The first available `identifierForVendor` (or a generated fallback before
/// first unlock) is persisted immediately in a device-local, non-backed-up
/// file. Every later launch reuses that choice, so a pre-unlock headless wake
/// cannot register one identity and the foreground launch silently switch to
/// another, while restoring a backup onto a second device cannot clone the
/// first installation's identity.
@MainActor
enum CurrentRecordingDeviceProvider {
    private enum Key: String {
        /// Pre-file-storage builds kept the identity here. `UserDefaults` is
        /// backed up, so this key is migration input only and is removed after
        /// the device-local file is created.
        case recordingDeviceID = "where.recordingDeviceID"
    }

    private static let identityFileName = "recording-device-id"

    static func current() throws -> CurrentRecordingDevice {
        let device = UIDevice.current
        let kind: RecordingDeviceKind = switch device.userInterfaceIdiom {
            case .phone: .phone
            case .pad: .tablet
            case .unspecified, .tv, .carPlay, .mac, .vision: .other
            @unknown default: .other
        }
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true,
        )
        return try current(
            identityFileURL: directory.appending(path: identityFileName),
            legacyDefaults: .standard,
            vendorID: device.identifierForVendor,
            systemName: device.model,
            kind: kind,
        )
    }

    /// Explicit-dependency factory used by the production composition method
    /// above and by tests that exercise backup restoration and pre-unlock
    /// identity resolution without touching the app sandbox.
    static func current(
        identityFileURL: URL,
        legacyDefaults: UserDefaults,
        vendorID: UUID?,
        systemName: String,
        kind: RecordingDeviceKind,
    ) throws -> CurrentRecordingDevice {
        let id = try identity(
            at: identityFileURL,
            legacyDefaults: legacyDefaults,
            vendorID: vendorID,
        )
        return CurrentRecordingDevice(
            id: RecordingDeviceID(rawValue: id),
            systemName: systemName,
            kind: kind,
        )
    }

    private static func identity(
        at fileURL: URL,
        legacyDefaults: UserDefaults,
        vendorID: UUID?,
    ) throws -> UUID {
        if FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) {
            let data = try Data(contentsOf: fileURL)
            guard let value = String(data: data, encoding: .utf8)
                .flatMap(UUID.init(uuidString:))
            else {
                throw CocoaError(
                    .fileReadCorruptFile,
                    userInfo: [NSFilePathErrorKey: fileURL.path(percentEncoded: false)],
                )
            }
            return value
        }

        // On the original device the vendor id matches the legacy preference;
        // after a restore it does not. Making the current vendor id authoritative
        // preserves the former and rotates the latter. Before first unlock there
        // is no vendor id, so mint the fallback directly in non-backed-up storage.
        let value = vendorID ?? UUID()

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true,
        )
        try Data(value.uuidString.utf8).write(
            to: fileURL,
            options: [.atomic, .noFileProtection],
        )
        var persistedURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try persistedURL.setResourceValues(resourceValues)
        legacyDefaults.removeObject(forKey: Key.recordingDeviceID.rawValue)
        return value
    }
}
