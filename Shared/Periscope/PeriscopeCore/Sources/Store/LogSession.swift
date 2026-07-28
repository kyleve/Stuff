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

/// Hand-written `init(from:)` for one load-bearing reason: a crash journal
/// written by a build without `attributes` is ingested by one that has them,
/// and synthesized decoding throws on the missing key rather than defaulting.
/// An older build simply couldn't name itself, which is an empty set of
/// attributes — not a corrupt session. `encode(to:)` stays synthesized.
extension LogSession {
    private enum CodingKeys: String, CodingKey {
        case id
        case startedAt
        case appVersion
        case buildNumber
        case osVersion
        case deviceModel
        case attributes
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        startedAt = try container.decode(Date.self, forKey: .startedAt)
        appVersion = try container.decode(String.self, forKey: .appVersion)
        buildNumber = try container.decode(String.self, forKey: .buildNumber)
        osVersion = try container.decode(String.self, forKey: .osVersion)
        deviceModel = try container.decode(String.self, forKey: .deviceModel)
        attributes = try container.decodeIfPresent(
            [LogSessionAttributeKey: String].self,
            forKey: .attributes,
        ) ?? [:]
    }
}
