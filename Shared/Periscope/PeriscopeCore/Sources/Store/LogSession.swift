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
    /// How this build was produced — commit, configuration, optimization
    /// level (see ``LogSessionAttributeKey``). The version and build number
    /// alone can't tell an optimized build from an unoptimized one, which is
    /// the difference between a span duration that means something and one
    /// that doesn't. Only the app knows these, so it supplies them.
    public let attributes: [LogSessionAttributeKey: String]

    public init(
        id: UUID,
        startedAt: Date,
        appVersion: String,
        buildNumber: String,
        osVersion: String,
        deviceModel: String,
        attributes: [LogSessionAttributeKey: String],
    ) {
        self.id = id
        self.startedAt = startedAt
        self.appVersion = appVersion
        self.buildNumber = buildNumber
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.attributes = attributes
    }

    /// A fresh session describing this launch: main-bundle version info, OS
    /// version, hardware model, and whatever build `attributes` the caller
    /// can name.
    public static func current(attributes: [LogSessionAttributeKey: String]) -> LogSession {
        let info = Bundle.main.infoDictionary ?? [:]
        return LogSession(
            id: UUID(),
            startedAt: Date(),
            appVersion: info["CFBundleShortVersionString"] as? String ?? "unknown",
            buildNumber: info["CFBundleVersion"] as? String ?? "unknown",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: hardwareModel(),
            attributes: attributes,
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
