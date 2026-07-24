import Foundation
import PortholeCore

/// The always-present built-in connector (id `app`): a one-row `app-info` data
/// source describing the running app/device, and a `ping` action that echoes its
/// input with a device timestamp — the end-to-end smoke test for every surface.
public final class AppInfoConnector: PortholeConnector {
    public let descriptor = PortholeConnectorDescriptor(
        id: "app",
        title: "App",
        summary: "Basic facts about the running app and device, plus a connectivity ping.",
        version: 1,
    )

    private let appName: String
    private let bundleID: String
    private let processStart = Date()

    public init(appName: String, bundleID: String) {
        self.appName = appName
        self.bundleID = bundleID
    }

    public func actions() -> [PortholeAction] {
        [
            PortholeAction(
                descriptor: PortholeActionDescriptor(
                    id: "ping",
                    title: "Ping",
                    summary: "Echoes the given message back with the device's current timestamp. Use to confirm the bridge is live.",
                    parameters: .object(["message": .string("Any text to echo back")]),
                    isDestructive: false,
                ),
                handler: { parameters in
                    .object([
                        "message": parameters["message"] ?? .null,
                        "timestamp": .date(Date()),
                    ])
                },
            ),
        ]
    }

    public func dataSources() -> [PortholeDataSource] {
        let appName = appName
        let bundleID = bundleID
        let processStart = processStart
        return [
            PortholeDataSource(
                descriptor: PortholeDataSourceDescriptor(
                    id: "app-info",
                    title: "App info",
                    summary: "A single row describing the running app, device, and OS.",
                    rowSchema: .object([
                        "appName": .string(),
                        "bundleID": .string(),
                        "version": .string(),
                        "build": .string(),
                        "deviceName": .string(),
                        "deviceModel": .string(),
                        "systemName": .string(),
                        "systemVersion": .string(),
                        "locale": .string(),
                        "uptimeSeconds": .number(),
                        "isDebugBuild": .boolean(),
                    ]),
                    filters: .object([:]),
                    supportsSubscription: false,
                ),
                fetch: { _ in
                    let info = Bundle.main.infoDictionary
                    let row: PortholeValue = .object([
                        "appName": .string(appName),
                        "bundleID": .string(bundleID),
                        "version": .string(info?["CFBundleShortVersionString"] as? String ??
                            "unknown"),
                        "build": .string(info?["CFBundleVersion"] as? String ?? "unknown"),
                        "deviceName": .string(DeviceInfo.deviceName),
                        "deviceModel": .string(DeviceInfo.model),
                        "systemName": .string(DeviceInfo.systemName),
                        "systemVersion": .string(DeviceInfo.systemVersion),
                        "locale": .string(Locale.current.identifier),
                        "uptimeSeconds": .double(Date().timeIntervalSince(processStart)),
                        "isDebugBuild": .bool(DeviceInfo.isDebugBuild),
                    ])
                    return PortholePage(rows: [row], nextCursor: nil, totalCount: 1)
                },
            ),
        ]
    }
}
