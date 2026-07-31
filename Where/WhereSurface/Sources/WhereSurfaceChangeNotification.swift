import CoreFoundation
import Foundation

/// The advisory Darwin notification posted after replacing the glance file.
///
/// The file remains authoritative: a receiver always re-reads it and may also
/// refresh at launch. Darwin delivery is intentionally only a low-latency hint.
public enum WhereSurfaceChangeNotification {
    public static let name = "com.stuff.where.surface.changed"

    public static func post() {
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(rawValue: name as CFString),
            nil,
            nil,
            true,
        )
    }
}
