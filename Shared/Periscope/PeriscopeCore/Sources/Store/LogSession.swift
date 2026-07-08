import Foundation

/// Per-launch resource metadata — OTel's `Resource`. Every persisted event
/// references the session that produced it, so weeks-old logs stay
/// attributable to a specific build on a specific device.
public struct LogSession: Sendable, Identifiable, Hashable, Codable {
    public let id: UUID
    public let startedAt: Date
    public let appVersion: String
    public let buildNumber: String
    public let osVersion: String
    public let deviceModel: String

    public init(
        id: UUID,
        startedAt: Date,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
    ) {
        self.id = id
        self.startedAt = startedAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
    }

    /// A fresh session describing this launch: main-bundle version info,
    /// OS version, and hardware model.
    public static func current() -> LogSession {
        let info = Bundle.main.infoDictionary ?? [:]
        return LogSession(
            id: UUID(),
            startedAt: Date(),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: hardwareModel(),
        )
    }

    /// The `uname` machine identifier (e.g. `iPhone17,1`, `arm64` on
    /// simulators and Macs).
    private static func hardwareModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        return withUnsafeBytes(of: &systemInfo.machine) { buffer in
            String(decoding: buffer.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
