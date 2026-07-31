import Foundation
import UIKit
import WhereCore

/// Resolves local recording participation at the app composition boundary.
///
/// On a participating iPhone or iPad, the first available
/// `identifierForVendor` (or a generated fallback before first unlock) is
/// persisted immediately. Every later launch reuses that choice, so a
/// pre-unlock headless wake cannot register one identity and the foreground
/// launch silently switch to another. Catalyst returns management-only before
/// reading or writing an identity.
@MainActor
enum CurrentRecordingDeviceProvider {
    private enum Key: String {
        case recordingDeviceID = "where.recordingDeviceID"
    }

    static func supportsLocalRecording(idiom: UIUserInterfaceIdiom) -> Bool {
        #if targetEnvironment(macCatalyst)
            return false
        #else
            switch idiom {
                case .phone, .pad: true
                case .unspecified, .tv, .carPlay, .mac, .vision: false
                @unknown default: false
            }
        #endif
    }

    static func participation(
        defaults: UserDefaults,
        idiom: UIUserInterfaceIdiom,
    ) -> RecordingParticipation {
        guard supportsLocalRecording(idiom: idiom) else { return .managementOnly }

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

        let kind: RecordingDeviceKind = switch idiom {
            case .phone: .phone
            case .pad: .tablet
            case .unspecified, .tv, .carPlay, .mac, .vision: .other
            @unknown default: .other
        }
        return .recording(
            device: CurrentRecordingDevice(
                id: RecordingDeviceID(rawValue: id),
                systemName: device.model,
                kind: kind,
            ),
            defaultEnabledForNewInstallation: idiom == .phone,
        )
    }

    /// Demo mode mirrors the host's physical-recording capability without
    /// minting a real installation identity. A management-only host stays
    /// management-only even inside its throwaway demo world.
    static func demoParticipation(
        supportsLocalRecording: Bool,
    ) -> RecordingParticipation {
        guard supportsLocalRecording else { return .managementOnly }
        return .recording(
            device: .preview,
            defaultEnabledForNewInstallation: true,
        )
    }

    static var demoParticipationForCurrentHost: RecordingParticipation {
        demoParticipation(
            supportsLocalRecording: supportsLocalRecording(
                idiom: UIDevice.current.userInterfaceIdiom,
            ),
        )
    }
}
