import Foundation
import UIKit
import WhereCore

/// Builds the local installation identity at the app composition boundary.
///
/// The first available `identifierForVendor` (or a generated fallback before
/// first unlock) is persisted immediately. Every later launch reuses that
/// choice, so a pre-unlock headless wake cannot register one identity and the
/// foreground launch silently switch to another.
@MainActor
enum CurrentRecordingDeviceProvider {
    private enum Key: String {
        case recordingDeviceID = "where.recordingDeviceID"
    }

    static func current(defaults: UserDefaults) -> CurrentRecordingDevice {
        let device = UIDevice.current
        let id: UUID
        if let stored = defaults.string(forKey: Key.recordingDeviceID.rawValue)
            .flatMap(UUID.init(uuidString:))
        {
            id = stored
        } else {
            id = device.identifierForVendor ?? UUID()
            defaults.set(id.uuidString, forKey: Key.recordingDeviceID.rawValue)
        }

        let kind: RecordingDeviceKind = switch device.userInterfaceIdiom {
            case .phone: .phone
            case .pad: .tablet
            case .unspecified, .tv, .carPlay, .mac, .vision: .other
            @unknown default: .other
        }
        return CurrentRecordingDevice(
            id: RecordingDeviceID(rawValue: id),
            systemName: device.model,
            kind: kind,
        )
    }
}
