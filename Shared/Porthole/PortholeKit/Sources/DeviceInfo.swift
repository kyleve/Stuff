import Foundation
#if canImport(UIKit)
    import UIKit
#endif

/// Cross-platform device/host facts for the hello handshake and the built-in
/// app-info connector. iOS reads `UIDevice`; other platforms fall back to
/// `ProcessInfo`/`Host`.
enum DeviceInfo {
    static var deviceName: String {
        #if canImport(UIKit)
            return UIDevice.current.name
        #else
            return ProcessInfo.processInfo.hostName
        #endif
    }

    static var model: String {
        #if canImport(UIKit)
            return UIDevice.current.model
        #else
            return "Mac"
        #endif
    }

    static var systemName: String {
        #if canImport(UIKit)
            return UIDevice.current.systemName
        #else
            return "macOS"
        #endif
    }

    static var systemVersion: String {
        #if canImport(UIKit)
            return UIDevice.current.systemVersion
        #else
            return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }

    static var isDebugBuild: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }
}
