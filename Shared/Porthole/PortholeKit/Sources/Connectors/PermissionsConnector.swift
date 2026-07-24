import Foundation
import PortholeCore
#if canImport(AVFoundation)
    import AVFoundation
#endif
#if canImport(CoreLocation)
    import CoreLocation
#endif
#if canImport(Photos)
    import Photos
#endif
#if canImport(UserNotifications)
    import UserNotifications
#endif

/// One permission's current authorization status.
public struct PermissionStatus: Sendable, Equatable {
    public var permission: String
    public var status: String

    public init(permission: String, status: String) {
        self.permission = permission
        self.status = status
    }
}

/// Reads permission statuses. A protocol so tests inject scripted values instead
/// of touching the real frameworks.
public protocol PermissionsReading: Sendable {
    /// Reads every known permission's status. Must never trigger a prompt.
    func statuses() async -> [PermissionStatus]
}

/// The built-in `permissions` connector: a single row per permission with its
/// authorization status. Reading never prompts. Auto-registered by ``Porthole``.
public final class PermissionsConnector: PortholeConnector {
    public let descriptor = PortholeConnectorDescriptor(
        id: "permissions",
        title: "Permissions",
        summary: "The app's current authorization status for notifications, location, camera, microphone, and photos. Reading never prompts.",
        version: 1,
    )

    private let reader: PermissionsReading

    public init() {
        reader = SystemPermissionsReader()
    }

    @_spi(Testing)
    public init(reader: PermissionsReading) {
        self.reader = reader
    }

    public func dataSources() -> [PortholeDataSource] {
        let reader = reader
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "permissions",
                    title: "Permissions",
                    summary: "One row per permission with its authorization status.",
                    rowSchema: .object(["permission": .string(), "status": .string()]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in
                    let rows = await reader.statuses().map { status in
                        PortholeValue.object([
                            "permission": .string(status.permission),
                            "status": .string(status.status),
                        ])
                    }
                    return PortholePage(rows: rows, totalCount: rows.count)
                },
            ),
        ]
    }
}

/// The production reader: each framework is behind its own `canImport`, and every
/// read is a status query that never surfaces a prompt.
public struct SystemPermissionsReader: PermissionsReading {
    public init() {}

    public func statuses() async -> [PermissionStatus] {
        var statuses: [PermissionStatus] = []
        await statuses.append(notificationStatus())
        statuses.append(contentsOf: captureStatuses())
        statuses.append(locationStatus())
        statuses.append(photosStatus())
        return statuses
    }

    private func notificationStatus() async -> PermissionStatus {
        #if canImport(UserNotifications)
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            let value = switch settings.authorizationStatus {
                case .notDetermined: "notDetermined"
                case .denied: "denied"
                case .authorized: "authorized"
                case .provisional: "provisional"
                case .ephemeral: "ephemeral"
                @unknown default: "unknown"
            }
            return PermissionStatus(permission: "notifications", status: value)
        #else
            return PermissionStatus(permission: "notifications", status: "unavailable")
        #endif
    }

    private func captureStatuses() -> [PermissionStatus] {
        #if canImport(AVFoundation)
            return [(AVMediaType.video, "camera"), (AVMediaType.audio, "microphone")]
                .map { type, name in
                    let value = switch AVCaptureDevice.authorizationStatus(for: type) {
                        case .notDetermined: "notDetermined"
                        case .restricted: "restricted"
                        case .denied: "denied"
                        case .authorized: "authorized"
                        @unknown default: "unknown"
                    }
                    return PermissionStatus(permission: name, status: value)
                }
        #else
            return []
        #endif
    }

    private func locationStatus() -> PermissionStatus {
        #if canImport(CoreLocation)
            let value = switch CLLocationManager().authorizationStatus {
                case .notDetermined: "notDetermined"
                case .restricted: "restricted"
                case .denied: "denied"
                case .authorizedAlways: "authorizedAlways"
                case .authorizedWhenInUse: "authorizedWhenInUse"
                @unknown default: "unknown"
            }
            return PermissionStatus(permission: "location", status: value)
        #else
            return PermissionStatus(permission: "location", status: "unavailable")
        #endif
    }

    private func photosStatus() -> PermissionStatus {
        #if canImport(Photos)
            let value = switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
                case .notDetermined: "notDetermined"
                case .restricted: "restricted"
                case .denied: "denied"
                case .authorized: "authorized"
                case .limited: "limited"
                @unknown default: "unknown"
            }
            return PermissionStatus(permission: "photos", status: value)
        #else
            return PermissionStatus(permission: "photos", status: "unavailable")
        #endif
    }
}
